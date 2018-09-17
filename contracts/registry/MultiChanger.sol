pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/ownership/CanReclaimToken.sol";
import "../interface/IMultiToken.sol";

contract IEtherToken is ERC20 {
    function deposit() public payable;
    function withdraw(uint256 _amount) public;
}

contract IBancorNetwork {
    function convert(
        address[] _path,
        uint256 _amount,
        uint256 _minReturn
    ) 
        public
        payable
        returns(uint256);

    function claimAndConvert(
        address[] _path,
        uint256 _amount,
        uint256 _minReturn
    ) 
        public
        payable
        returns(uint256);
}

contract IKyberNetworkProxy {
    function trade(
        address src,
        uint srcAmount,
        address dest,
        address destAddress,
        uint maxDestAmount,
        uint minConversionRate,
        address walletId
    )
        public
        payable
        returns(uint);
}


contract MultiChanger is CanReclaimToken {
    using SafeMath for uint256;

    // Source: https://github.com/gnosis/MultiSigWallet/blob/master/contracts/MultiSigWallet.sol
    // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function externalCall(address destination, uint value, bytes data, uint dataOffset, uint dataLength) internal returns (bool result) {
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                sub(gas, 34710),   // 34710 is the value that solidity is currently emitting
                                   // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                                   // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
                destination,
                value,
                add(d, dataOffset),
                dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0                  // Output is ignored, therefore the output size is zero
            )
        }
    }

    function change(
        bytes _callDatas,
        uint[] _starts // including 0 and LENGTH values
    )
        internal
    {
        for (uint i = 0; i < _starts.length - 1; i++) {
            require(externalCall(this, 0, _callDatas, _starts[i], _starts[i + 1] - _starts[i]));
        }
    }

    function sendEthValue(address _target, bytes _data, uint256 _value) external {
        require(_target.call.value(_value)(_data));
    }

    function sendEthProportion(address _target, bytes _data, uint256 _mul, uint256 _div) external {
        uint256 value = address(this).balance.mul(_mul).div(_div);
        require(_target.call.value(value)(_data));
    }

    function approveTokenAmount(address _target, bytes _data, ERC20 _fromToken, uint256 _amount) external {
        if (_fromToken.allowance(this, _target) != 0) {
            _fromToken.approve(_target, 0);
        }
        _fromToken.approve(_target, _amount);
        require(_target.call(_data));
    }

    function approveTokenProportion(address _target, bytes _data, ERC20 _fromToken, uint256 _mul, uint256 _div) external {
        uint256 amount = _fromToken.balanceOf(this).mul(_mul).div(_div);
        if (_fromToken.allowance(this, _target) != 0) {
            _fromToken.approve(_target, 0);
        }
        _fromToken.approve(_target, amount);
        require(_target.call(_data));
    }

    function transferTokenAmount(address _target, bytes _data, ERC20 _fromToken, uint256 _amount) external {
        _fromToken.transfer(_target, _amount);
        require(_target.call(_data));
    }

    function transferTokenProportion(address _target, bytes _data, ERC20 _fromToken, uint256 _mul, uint256 _div) external {
        uint256 amount = _fromToken.balanceOf(this).mul(_mul).div(_div);
        _fromToken.transfer(_target, amount);
        require(_target.call(_data));
    }

    // Ether token

    function withdrawEtherTokenAmount(IEtherToken _etherToken, uint256 _amount) external {
        _etherToken.withdraw(_amount);
    }

    function withdrawEtherTokenProportion(IEtherToken _etherToken, uint256 _mul, uint256 _div) external {
        uint256 amount = _etherToken.balanceOf(this).mul(_mul).div(_div);
        _etherToken.withdraw(amount);
    }

    // Bancor Network

    function bancorSendEthValue(IBancorNetwork _bancor, address[] _path, uint256 _value) external {
        _bancor.convert.value(_value)(_path, _value, 1);
    }

    function bancorSendEthProportion(IBancorNetwork _bancor, address[] _path, uint256 _mul, uint256 _div) external {
        uint256 value = address(this).balance.mul(_mul).div(_div);
        _bancor.convert.value(value)(_path, value, 1);
    }

    function bancorApproveTokenAmount(IBancorNetwork _bancor, address[] _path, uint256 _amount) external {
        if (ERC20(_path[0]).allowance(this, _bancor) == 0) {
            ERC20(_path[0]).approve(_bancor, uint256(-1));
        }
        _bancor.claimAndConvert(_path, _amount, 1);
    }

    function bancorApproveTokenProportion(IBancorNetwork _bancor, address[] _path, uint256 _mul, uint256 _div) external {
        uint256 amount = ERC20(_path[0]).balanceOf(this).mul(_mul).div(_div);
        if (ERC20(_path[0]).allowance(this, _bancor) == 0) {
            ERC20(_path[0]).approve(_bancor, uint256(-1));
        }
        _bancor.claimAndConvert(_path, amount, 1);
    }

    function bancorTransferTokenAmount(IBancorNetwork _bancor, address[] _path, uint256 _amount) external {
        ERC20(_path[0]).transfer(_bancor, _amount);
        _bancor.convert(_path, _amount, 1);
    }

    function bancorTransferTokenProportion(IBancorNetwork _bancor, address[] _path, uint256 _mul, uint256 _div) external {
        uint256 amount = ERC20(_path[0]).balanceOf(this).mul(_mul).div(_div);
        ERC20(_path[0]).transfer(_bancor, amount);
        _bancor.convert(_path, amount, 1);
    }

    function bancorAlreadyTransferedTokenAmount(IBancorNetwork _bancor, address[] _path, uint256 _amount) external {
        _bancor.convert(_path, _amount, 1);
    }

    function bancorAlreadyTransferedTokenProportion(IBancorNetwork _bancor, address[] _path, uint256 _mul, uint256 _div) external {
        uint256 amount = ERC20(_path[0]).balanceOf(_bancor).mul(_mul).div(_div);
        _bancor.convert(_path, amount, 1);
    }

    // Kyber Network

    function kyberSendEthProportion(IKyberNetworkProxy _kyber, ERC20 _fromToken, address _toToken, uint256 _mul, uint256 _div) external {
        uint256 value = address(this).balance.mul(_mul).div(_div);
        _kyber.trade.value(value)(
            _fromToken,
            value,
            _toToken,
            this,
            1 << 255,
            0,
            0
        );
    }

    function kyberApproveTokenAmount(IKyberNetworkProxy _kyber, ERC20 _fromToken, address _toToken, uint256 _amount) external {
        if (_fromToken.allowance(this, _kyber) == 0) {
            _fromToken.approve(_kyber, uint256(-1));
        }
        _kyber.trade(
            _fromToken,
            _amount,
            _toToken,
            this,
            1 << 255,
            0,
            0
        );
    }

    function kyberApproveTokenProportion(IKyberNetworkProxy _kyber, ERC20 _fromToken, address _toToken, uint256 _mul, uint256 _div) external {
        uint256 amount = _fromToken.balanceOf(this).mul(_mul).div(_div);
        this.kyberApproveTokenAmount(_kyber, _fromToken, _toToken, amount);
    }
}