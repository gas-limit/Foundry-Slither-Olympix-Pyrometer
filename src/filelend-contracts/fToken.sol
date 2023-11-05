// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "/home/gas_limit/ethonline-filecoin-project/backend/node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "/home/gas_limit/ethonline-filecoin-project/backend/node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IOracle {
    function getPrice(address token) external view returns (uint256);
}

contract P2PLending is ERC20 {
    using SafeERC20 for IERC20;

    // Custom Errors
    error InvalidAmount(uint256 provided, string reason);
    error InvalidAddress(address providedAddress, string reason);
    error ActiveBorrowNotFound();
    error InsufficientCollateral(uint256 requiredCollateralRatio, uint256 currentCollateralRatio);
    error CannotLiquidate(uint256 currentCollateralRatio);
    error NotOwner(address caller);

    // Events
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 borrowAmount, uint256 collateralAmount);
    event Repaid(address indexed user, uint256 repayAmount);
    event CollateralAdded(address indexed user, uint256 collateralAmount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 amountLiquidated);
    event CollateralRatioUpdated(uint256 indexed newRatio);
    event LiquidationBonusUpdated(uint256 indexed newBonus);
    event BaseBorrowRateUpdated(uint256 indexed newRate);
    event MaxBorrowRateUpdated(uint256 indexed newRate);


    struct Borrower {
        uint256 collateralAmount;
        uint256 borrowedAmount;
        uint256 lastActionTimestamp;
    }

    // A struct to track depositor details
    struct Depositor {
        uint256 amount;                 // Amount of stablecoins deposited
        uint256 lastUpdated;            // Timestamp of last deposit/withdrawal
        uint256 accumulatedInterestRate; // The global accumulated interest rate when last deposit/withdrawal happened
    }


    address public owner;

    IERC20 public stablecoin;
    IERC20 public collateralToken;
    IOracle public oracle;

    mapping(address => Borrower) public borrowers;
    mapping(address => Depositor) public depositors;

    uint256 public totalDeposited;
    uint256 public totalBorrowed;
    uint256 public lastUpdated;
    uint256 public accumulatedInterestRate = 0; // This represents the accumulated interest rate globally

    uint256 private constant SCALING_FACTOR = 1e36;

    uint256 public COLLATERAL_RATIO;
    uint256 public LIQUIDATION_BONUS;
    uint256 public BASE_BORROW_RATE;
    uint256 public MAX_BORROW_RATE;

    uint256 public constant INTEREST_INTERVAL = 1 days;



    constructor(address _stablecoin, address _collateralToken, address _oracle) 
        ERC20("fToken", "fLend") {
       if(_stablecoin == address(0) || _collateralToken == address(0) || _oracle == address(0)) {
            revert InvalidAddress(address(0), "Invalid address provided");
        }
        owner = msg.sender;
        stablecoin = IERC20(_stablecoin);
        collateralToken = IERC20(_collateralToken);
        oracle = IOracle(_oracle);
        lastUpdated = block.timestamp;

        COLLATERAL_RATIO = 150 * SCALING_FACTOR;
        LIQUIDATION_BONUS = 110 * SCALING_FACTOR;
        BASE_BORROW_RATE = 2 * SCALING_FACTOR;
        MAX_BORROW_RATE = 15 * SCALING_FACTOR;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    function getCurrentInterest() internal view returns (uint256) {
        uint256 intervalsElapsed = (block.timestamp - lastUpdated) / INTEREST_INTERVAL;
        uint256 supply = totalDeposited - totalBorrowed;
        return supply * calculateBorrowRate() * intervalsElapsed * INTEREST_INTERVAL / SCALING_FACTOR / 365 days;
    }

    function getTokenValue(IERC20 token, uint256 amount) internal view returns (uint256) {
        return oracle.getPrice(address(token)) * amount;
    }

    function calculateBorrowRate() internal view returns (uint256) {
        uint256 utilization = (totalBorrowed * SCALING_FACTOR * 100) / totalDeposited;
        return BASE_BORROW_RATE + (utilization * (MAX_BORROW_RATE - BASE_BORROW_RATE)) / SCALING_FACTOR;
    }

    function calculateBorrowerInterest(address borrowerAddress) internal view returns (uint256) {
        Borrower storage borrower = borrowers[borrowerAddress];
        uint256 intervalsElapsed = (block.timestamp - borrower.lastActionTimestamp) / INTEREST_INTERVAL;
        return borrower.borrowedAmount * calculateBorrowRate() * intervalsElapsed * INTEREST_INTERVAL / SCALING_FACTOR / 365 days;
    }


    function updateTimestamp() internal {
        lastUpdated = block.timestamp;
    }

    function deposit(uint256 amount) external {
        if (amount <= 0) revert InvalidAmount(amount, "Amount should be greater than 0");

        // Handle previous deposit interest first
        if(depositors[msg.sender].amount > 0) {
            uint256 interest = (depositors[msg.sender].amount * (accumulatedInterestRate - depositors[msg.sender].accumulatedInterestRate)) / SCALING_FACTOR;
            depositors[msg.sender].amount += interest;
            totalDeposited += interest;
        }

        depositors[msg.sender].amount += amount;
        depositors[msg.sender].lastUpdated = block.timestamp;
        depositors[msg.sender].accumulatedInterestRate = accumulatedInterestRate;

        updateTimestamp();
        
        emit Deposited(msg.sender, amount);
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);
        
    }

    function withdraw(uint256 amount) external {
        require(depositors[msg.sender].amount >= amount, "Insufficient funds");
        
        // Calculate interest
        uint256 interest = (depositors[msg.sender].amount * (accumulatedInterestRate - depositors[msg.sender].accumulatedInterestRate)) / SCALING_FACTOR;
        
        depositors[msg.sender].amount += interest - amount;  // Add interest and subtract the withdrawal amount
        totalDeposited += interest - amount * SCALING_FACTOR; 

        depositors[msg.sender].lastUpdated = block.timestamp;
        depositors[msg.sender].accumulatedInterestRate = accumulatedInterestRate;

        updateTimestamp();
        accumulateInterest();
        
        stablecoin.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function borrow(uint256 borrowAmount, uint256 collateralAmount) external {
        if (borrowAmount <= 0 || collateralAmount <= 0) revert InvalidAmount(borrowAmount, "Both borrow and collateral amounts should be greater than 0");

        uint256 stablecoinValue = getTokenValue(stablecoin, borrowAmount);
        uint256 collateralValue = getTokenValue(collateralToken, collateralAmount);
        if ((collateralValue * SCALING_FACTOR * 100) / stablecoinValue < COLLATERAL_RATIO)
            revert InsufficientCollateral(COLLATERAL_RATIO, (collateralValue * SCALING_FACTOR * 100) / stablecoinValue);

        borrowers[msg.sender] = Borrower(collateralAmount * SCALING_FACTOR, borrowAmount * SCALING_FACTOR, block.timestamp);
        totalBorrowed += borrowAmount * SCALING_FACTOR;
        updateTimestamp();
        accumulateInterest();

        stablecoin.safeTransfer(msg.sender, borrowAmount);
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);

        emit Borrowed(msg.sender, borrowAmount, collateralAmount);
    }

    function repayBorrow(uint256 repayAmount) external {
        if (repayAmount <= 0) revert InvalidAmount(repayAmount, "Repay amount should be greater than 0");

        Borrower storage borrower = borrowers[msg.sender];

        borrower.borrowedAmount += calculateBorrowerInterest(msg.sender); // Add accrued interest
        borrower.lastActionTimestamp = block.timestamp; // Update the last action timestamp

        // Ensure the borrower is not trying to repay more than what they owe
        if (borrower.borrowedAmount < repayAmount * SCALING_FACTOR) revert InvalidAmount(repayAmount, "Invalid repay amount");

        borrower.borrowedAmount -= repayAmount * SCALING_FACTOR;
        totalBorrowed -= repayAmount * SCALING_FACTOR;
        updateTimestamp();

        // If borrower's debt is fully repaid, release all collateral
        if (borrower.borrowedAmount == 0) {
            uint256 collateralToReturn = borrower.collateralAmount / SCALING_FACTOR;
            borrower.collateralAmount = 0;
            collateralToken.safeTransfer(msg.sender, collateralToReturn);
        }

        accumulateInterest();

        stablecoin.safeTransferFrom(msg.sender, address(this), repayAmount);

        emit Repaid(msg.sender, repayAmount);
    }

    function addCollateral(uint256 collateralAmount) external {
        if (collateralAmount <= 0) revert InvalidAmount(collateralAmount, "Collateral amount should be greater than 0");

        Borrower storage borrower = borrowers[msg.sender];
        if (borrower.borrowedAmount == 0) revert ActiveBorrowNotFound();

        borrower.collateralAmount += collateralAmount * SCALING_FACTOR;
        accumulateInterest();

        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);

        emit CollateralAdded(msg.sender, collateralAmount);
    }

    function calculateBorrowFee(uint256 amount) public view returns (uint256) {
        return (amount * calculateBorrowRate()) / 100 / SCALING_FACTOR;
    }

    function liquidate(address user) external {
        Borrower storage borrower = borrowers[user];
        
        // Calculate how much debt needs to be repaid for this liquidation.
        uint256 borrowedValue = getTokenValue(stablecoin, borrower.borrowedAmount / SCALING_FACTOR);
        uint256 collateralValue = getTokenValue(collateralToken, borrower.collateralAmount / SCALING_FACTOR);
        uint256 requiredCollateralValue = (borrowedValue * COLLATERAL_RATIO) / SCALING_FACTOR;
        uint256 shortfallValue = requiredCollateralValue - collateralValue;
        uint256 debtToRepay = shortfallValue / oracle.getPrice(address(stablecoin));

        // Ensure the liquidator has provided enough stablecoin for this liquidation.
        require(stablecoin.balanceOf(msg.sender) >= debtToRepay, "Not enough stablecoin to liquidate");

        if ((collateralValue * SCALING_FACTOR * 100) / borrower.borrowedAmount >= COLLATERAL_RATIO)
            revert CannotLiquidate((collateralValue * SCALING_FACTOR * 100) / borrower.borrowedAmount);

        uint256 requiredCollateral = (shortfallValue * SCALING_FACTOR) / oracle.getPrice(address(collateralToken));
        uint256 liquidationBonus = (requiredCollateral * LIQUIDATION_BONUS) / SCALING_FACTOR;
        uint256 totalCollateralToLiquidator = requiredCollateral + liquidationBonus;
        if (totalCollateralToLiquidator > borrower.collateralAmount) {
            totalCollateralToLiquidator = borrower.collateralAmount;
        }

        // Transfer stablecoin from liquidator to the contract.
        stablecoin.safeTransferFrom(msg.sender, address(this), debtToRepay);

        // Reduce borrower's debt.
        borrower.borrowedAmount -= debtToRepay * SCALING_FACTOR;
        totalBorrowed -= debtToRepay * SCALING_FACTOR;

        // Send the collateral token to the liquidator.
        borrower.collateralAmount -= totalCollateralToLiquidator;

        accumulateInterest();

        collateralToken.safeTransfer(msg.sender, totalCollateralToLiquidator / SCALING_FACTOR);

        emit Liquidated(user, msg.sender, totalCollateralToLiquidator / SCALING_FACTOR);
    }

    function partialLiquidate(address user, uint256 repayAmount) external {
        Borrower storage borrower = borrowers[user];

        // Ensure the repayAmount is valid
        require(repayAmount > 0 && repayAmount <= borrower.borrowedAmount / SCALING_FACTOR, "Invalid repay amount");

        // Calculate how much debt needs to be repaid for this liquidation.
        uint256 borrowedValue = getTokenValue(stablecoin, borrower.borrowedAmount / SCALING_FACTOR);
        uint256 collateralValue = getTokenValue(collateralToken, borrower.collateralAmount / SCALING_FACTOR);
        uint256 requiredCollateralValue = (borrowedValue * COLLATERAL_RATIO) / SCALING_FACTOR;
        
        if ((collateralValue * SCALING_FACTOR * 100) / borrower.borrowedAmount >= COLLATERAL_RATIO)
            revert CannotLiquidate((collateralValue * SCALING_FACTOR * 100) / borrower.borrowedAmount);

        uint256 shortfallValue = requiredCollateralValue - collateralValue;
        uint256 requiredCollateral = (shortfallValue * SCALING_FACTOR) / oracle.getPrice(address(collateralToken));
        
        // Calculate the amount of collateral for the partial liquidation
        uint256 liquidationCollateralAmount = (requiredCollateral * repayAmount * SCALING_FACTOR) / borrower.borrowedAmount;
        uint256 liquidationBonus = (liquidationCollateralAmount * LIQUIDATION_BONUS) / SCALING_FACTOR;
        uint256 totalCollateralToLiquidator = liquidationCollateralAmount + liquidationBonus;

        if (totalCollateralToLiquidator > borrower.collateralAmount) {
            totalCollateralToLiquidator = borrower.collateralAmount;
        }

        // Transfer stablecoin from liquidator to the contract.
        stablecoin.safeTransferFrom(msg.sender, address(this), repayAmount);

        // Reduce borrower's debt.
        borrower.borrowedAmount -= repayAmount * SCALING_FACTOR;
        totalBorrowed -= repayAmount * SCALING_FACTOR;

        // Send the collateral token to the liquidator.
        borrower.collateralAmount -= totalCollateralToLiquidator;
        
        accumulateInterest();
        collateralToken.safeTransfer(msg.sender, totalCollateralToLiquidator / SCALING_FACTOR);

        emit Liquidated(user, msg.sender, totalCollateralToLiquidator / SCALING_FACTOR);
    }

    function accumulateInterest() public {
        // Compute the global interest based on the interest paid by borrowers.
        // Here we're assuming depositors get 50% of the total interest charged to borrowers.
        uint256 globalInterest = getCurrentInterest() / 2;

        // Add the global interest rate increment to the accumulated interest rate.
        accumulatedInterestRate += (globalInterest * SCALING_FACTOR) / totalDeposited;

        // Increase the total deposited amount by the interest.
        totalDeposited += globalInterest;

        updateTimestamp();
    }



    // admin functions
    function setCollateralRatio(uint256 _newRatio) external onlyOwner {
        require(_newRatio > 110 * SCALING_FACTOR, "Collateral ratio too low");
        COLLATERAL_RATIO = _newRatio;
        emit CollateralRatioUpdated(_newRatio);
    }

    function setLiquidationBonus(uint256 _newBonus) external onlyOwner {
        require(_newBonus < 50 * SCALING_FACTOR, "Liquidation bonus too high");
        LIQUIDATION_BONUS = _newBonus;
        emit LiquidationBonusUpdated(_newBonus);
    }

    function setBaseBorrowRate(uint256 _newRate) external onlyOwner {
        require(_newRate < MAX_BORROW_RATE, "Base rate cannot be higher than max rate");
        BASE_BORROW_RATE = _newRate;
        emit BaseBorrowRateUpdated(_newRate);
    }

    function setMaxBorrowRate(uint256 _newRate) external onlyOwner {
        require(_newRate >= BASE_BORROW_RATE, "Max rate cannot be lower than base rate");
        require(_newRate <= 50 * SCALING_FACTOR, "Max rate too high");
        MAX_BORROW_RATE = _newRate;
        emit MaxBorrowRateUpdated(_newRate);
    }

}
