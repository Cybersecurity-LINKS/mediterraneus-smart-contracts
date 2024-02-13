// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./Deployer.sol";
import "../interfaces/IERC721Base.sol";
import "../interfaces/IERC721Factory.sol";
import "../interfaces/IERC20Base.sol";
import "../interfaces/IFixedRateExchange.sol";
import "../interfaces/IIDentity.sol";

contract ERC721Factory is Ownable, Deployer, IERC721Factory {
    using SafeMath for uint256;

    uint256 private currentNFTCount;
    mapping(address => address) public createdERC721List;
    mapping(address => address) public eRC721_to_owner;
    address[] public erc721addresses;

    mapping(address => address) public createdERC20List;
    mapping(address => address) public eRC20_to_owner;
    address[] public erc20addresses;

    address private _router;
    address private _fresc_address;
    address private _identity_addr;

    struct PublishData {
        string name;
        string symbol;
        string tokenURI; // enc CID
        string asset_download_URL;
        string asset_hash;
        string offering_hash;
        string trust_sign;
        string dt_name;
        string dt_symbol;
        uint256 maxSupply_; // must be > 10 otherwise mint will fail
        // uint256 vc_id; // TODO: remove this field, useless, we can get the VC id from the msg.sender and interacting with the identity contract
    }

    struct ContractBase {
        address baseAddress;
        bool isActive;
    }
    ContractBase private base721ContractInfo;
    ContractBase private base20ContractInfo;

    event Base721Added(address indexed _baseAddress, bool _isActive);

    event NFTCreated(
        address newTokenAddress,
        address templateAddress,
        string tokenName,
        address admin,
        string symbol,
        string tokenURI
    );

    // contract owner = minter
    event ERC20ContractDeployed(
        address contractAddress, 
        address contractOwner, 
        string name, 
        string symbol
    );

    constructor(address _base721Address, address _base20Address, address router_, address fresc_address_, address identity_addr_) {
        require(_base721Address != address(0), "Invalid ERC721Base contract address");
        require(_base20Address != address(0), "Invalid ERC721Base contract address");
        require(router_ != address(0), "Invalid router contract address");
        currentNFTCount = 0;
        addERC721Basetemplate(_base721Address);
        addERC20Basetemplate(_base20Address);
        _router = router_;
        _fresc_address = fresc_address_;
        _identity_addr = identity_addr_;
    }

    function publishAllinOne(
        PublishData memory _publishData
    ) public returns(address erc721token){
        /**
         * Verify vc is active and not expired/revoked. The "isVCRevoked" function checks if the vc is 
         * 1. Active
         * 2. Not expired
         * 3. Not revoked
        */
        IIDentity identity_token = IIDentity(_identity_addr);
        require(!identity_token.isVCRevoked_Addr(msg.sender), "The user does not have a valid VC!"); 
        // require(!identity_token.isVCRevoked(_publishData.vc_id), "The user does not have a valid VC!");
        // TODO: ? check if it is active and not expired
        /** 
         *  deploy NFT token
        */
        erc721token = deployERC721Contract(
            _publishData
        );
        IERC721Base ierc721Instance = IERC721Base(erc721token);
        require(ierc721Instance.balanceOf(msg.sender) == 1, "NFT not minted");
        /** 
         *  deploy DT token and mint some tokens
        */
        // deployERC20Contract + addNewErc20token do the same as the 'createDataToken()' of ERC721Base.sol
        address erc20token = deployERC20Contract(
            _publishData.dt_name,
            _publishData.dt_symbol,
            msg.sender,
            erc721token,
            _publishData.maxSupply_,
            true
        );
        ierc721Instance.addNewErc20token(erc20token);
        IERC20Base ierc20Instance = IERC20Base(erc20token);
        require(ierc20Instance.balanceOf(msg.sender) == 10e18, "Mint of DTs failed");
        /**
         * add DT to the FR Exchange and increase allowance for the FRESC
        */
        bytes32 _exchangeID = ierc20Instance.createFixedRate(
            _fresc_address,
            1e16,
            0
        );
        IFixedRateExchange iFRE = IFixedRateExchange(_fresc_address);
        require(iFRE.isExchangeActive(_exchangeID), "FRE not activated. Aborting");
        ierc20Instance.allInOne_approve(msg.sender, _fresc_address, 1e18);
        require(ierc20Instance.allowance(msg.sender, _fresc_address) == 1e18, "Allowance does not match approved value");
        emit NFTCreated(erc721token, base721ContractInfo.baseAddress, _publishData.name, msg.sender, _publishData.symbol, _publishData.tokenURI);
    }

    function deployERC721Contract(
        PublishData memory _publishData
    ) public returns(address erc721Instance){
        require(msg.sender != address(0), "address(0) cannot be an owner");
        require(base721ContractInfo.baseAddress != address(0), "DeployER721Contract: invalid base address");
        require(base721ContractInfo.isActive, "DeployERC721Contract: Base contract not active");

        erc721Instance = deploy(base721ContractInfo.baseAddress);
        require(erc721Instance != address(0), "deployERC721Contract: Failed to deploy new ERC721 contract");
        
        erc721addresses.push(erc721Instance);
        createdERC721List[erc721Instance] = erc721Instance;
        eRC721_to_owner[erc721Instance] = msg.sender;
        currentNFTCount += 1;
        
        IERC721Base ierc721Instance = IERC721Base(erc721Instance);
        require(ierc721Instance.initialize(
            msg.sender,
            address(this),
            _publishData.name,
            _publishData.symbol,
            _publishData.tokenURI,
            _publishData.asset_download_URL,
            _publishData.asset_hash,
            _publishData.offering_hash,
            _publishData.trust_sign
        ) == true, "Factory: Could not initialize New NFT contract");
        emit NFTCreated(erc721Instance, base721ContractInfo.baseAddress, _publishData.name, msg.sender, _publishData.symbol, _publishData.tokenURI);
    }

    function deployERC20Contract(
        string memory name_,
        string memory symbol_,
        address owner_, // minter = DT owner = NFT owner
        address erc721address_, // should be the calling NFT contract = msg.sender. If "all in one" the factory specifies the erc721address.
        uint256 maxSupply_,
        bool is_from_all_inOne
    ) public returns (address erc20Instance) {
        require(msg.sender != address(0), "address(0) cannot be an owner");

        if(is_from_all_inOne) { // the factory is calling this method (msg.sender = factory)
            require(owner_ == IERC721Base(createdERC721List[erc721address_]).getNFTowner(), "Provided minter is not the NFT owner!");
            require(createdERC721List[erc721address_] == erc721address_, "Provided NFT contract does not exist");
        } else { // the NFT owner is calling this methods leveraging the createDataToken from ERC721Base
            require(createdERC721List[msg.sender] == msg.sender, "Call coming from a non existing NFT contract deployed by this factory");
            require(owner_ == IERC721Base(createdERC721List[msg.sender]).getNFTowner(), "Provided minter is not the NFT owner!");
        }

        erc20Instance = deploy(base20ContractInfo.baseAddress);
        require(erc20Instance != address(0), "deployERC20Contract: Failed to deploy new ERC20 contract");
        
        erc20addresses.push(erc20Instance);
        createdERC20List[erc20Instance] = erc20Instance;
        eRC20_to_owner[erc20Instance] = owner_;

        IERC20Base ierc20Instance = IERC20Base(erc20Instance);
        require(ierc20Instance.initialize(
            name_,
            symbol_,
            owner_,
            erc721address_,
            _router,
            address(this),
            maxSupply_
        ), "DT initialization failed!");
        emit ERC20ContractDeployed(erc20Instance, owner_, name_, symbol_);
    }

    function addERC721Basetemplate(address _baseAddress) internal onlyOwner {
        require(_baseAddress != address(0), "Address(0) NOT allowed for base NFTcontract");
        require(_isContract(_baseAddress), "Provided address is NOT a contract");
        base721ContractInfo = ContractBase(_baseAddress, true);
        emit Base721Added(base721ContractInfo.baseAddress, base721ContractInfo.isActive);
    }

    function addERC20Basetemplate(address _baseAddress) internal onlyOwner {
        require(_baseAddress != address(0), "Address(0) NOT allowed for base NFTcontract");
        require(_isContract(_baseAddress), "Provided address is NOT a contract");
        base20ContractInfo = ContractBase(_baseAddress, true);
        emit Base721Added(base20ContractInfo.baseAddress, base20ContractInfo.isActive);
    }

    function _isContract(address account) internal view onlyOwner returns (bool){
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function getNFTCreatedCount() external view returns(uint256) {
        return currentNFTCount;
    }

    function getAllNFTCreatedAddress() external view returns(address[] memory) {
        return erc721addresses;
    }

    function getNFTCreatedAddress(address creator) external view returns(address[] memory ret) {
        for(uint256 i = 0; i < currentNFTCount; i++) {
            if(creator == eRC721_to_owner[erc721addresses[i]])
                ret[i] = erc721addresses[i];
        }
        return ret;
    }

    function getBase721ContractAddress() external view returns(address) {
        return base721ContractInfo.baseAddress;
    }
    
    function getBase20ContractAddress() external view returns(address) {
        return base20ContractInfo.baseAddress;
    }

    /**
     * @dev fallback function
     *      this is a default fallback function in which receives
     *      the collected ether.
     */
    fallback() external payable {}

    /**
     * @dev receive function
     *      this is a default receive function in which receives
     *      the collected ether.
     */
    receive() external payable {}
}
