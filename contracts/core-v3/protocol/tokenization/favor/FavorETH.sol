// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {ERC20} from "../../../dependencies/openzeppelin/contracts/ERC20.sol";
import {Ownable} from "../../../dependencies/openzeppelin/contracts/Ownable.sol";

contract FavorETH is ERC20, Ownable {
    // Name
    string private constant NAME = "Favor ETH";
    // Symbol
    string private constant SYMBOL = "FAVOR ETH";
    // 100% percentage
    uint256 public constant MULTIPLIER = 10000;

    // Buy tax percentage
    uint256 public buyTax = 0;
    // Sell tax percentage
    uint256 public sellTax = 5000;
    // Address to collect tax
    address public treasury;

    // to track buy/sell
    mapping(address => bool) public isMarketPair;
    // to track tax-exempt addresses
    mapping(address => bool) public isTaxExempt;

    constructor(uint256 initialSupply, address _treasury) ERC20(NAME, SYMBOL) {
        _mint(msg.sender, initialSupply * 10 ** decimals());
        treasury = _treasury;
    }

    // Function to update treasury
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    // Function to set buy tax
    function setBuyTax(uint256 _buyTax) external onlyOwner {
        require(_buyTax <= MULTIPLIER, "Buy tax too high");
        buyTax = _buyTax;
    }

    // Function to set sell tax
    function setSellTax(uint256 _sellTax) external onlyOwner {
        require(_sellTax <= MULTIPLIER, "Sell tax too high");
        sellTax = _sellTax;
    }

    // Function to add/remove tax exemption for addresses
    function setTaxExempt(address account, bool exempt) external onlyOwner {
        isTaxExempt[account] = exempt;
    }

    // Function to set market pair (e.g., for identifying buy/sell addresses)
    function setMarketPair(address pair, bool value) external onlyOwner {
        isMarketPair[pair] = value;
    }

    // Function to identify if the transaction is a buy
    function _isBuy(
        address sender,
        address recipient
    ) internal view returns (bool) {
        return isMarketPair[sender] && recipient != address(this);
    }

    // Function to identify if the transaction is a sell
    function _isSell(
        address sender,
        address recipient
    ) internal view returns (bool) {
        return isMarketPair[recipient] && sender != address(this);
    }

    // Overriding the _transfer function to apply taxes
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        uint256 taxAmount = 0;

        // Check if sender or recipient is exempt from tax
        if (isTaxExempt[sender] || isTaxExempt[recipient]) {
            super._transfer(sender, recipient, amount); // No tax, just transfer
            return;
        }

        if (_isBuy(sender, recipient)) {
            taxAmount = (amount * buyTax) / MULTIPLIER; // Buy tax logic
        } else if (_isSell(sender, recipient)) {
            taxAmount = (amount * sellTax) / MULTIPLIER; // Sell tax logic
        }

        if (taxAmount > 0) {
            super._transfer(sender, treasury, taxAmount); // Send tax to tax wallet
            amount -= taxAmount; // Deduct tax from the amount
        }

        super._transfer(sender, recipient, amount); // Transfer the remaining amount
    }
}
