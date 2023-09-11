//SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.0;

import "hardhat/console.sol";

contract store {

    enum Role { 
        USER, 
        STORE, 
        SUPPLIER 
    }
    
    struct User {
        address addr;
        Role role;
        bool registered;
        uint8 discount;
        bool requestedRoleChange;
        Role changeRoleTo;
    }

    struct Product {
        string title;
        uint256 cost_wei;
        uint256 amount;
        uint256 production_date;
        uint32 storage_life_days;
        Role received_as;
    }

    struct Record {
        address payable buyer;
        address seller;
        string title;
        uint256 cost_wei;
        uint256 amount;
        uint256 production_date;
        uint32 storage_life_days;
        uint32 rand_nonce;
        bool refunded;
        bool refund_rejected;
    }

    Record[] history;

    address payable[] credits;

    address[] suppliers;
    address[] stores;
    address[] users;
    address[] changeRoleRequests;

    uint256[] refundRequests;
    uint256[] refundRequestsTime;
    
    address owner = msg.sender;

    uint256 constant SUPPLIERCODE = 47329578451307523169892330890226538014635940820510227072738242430834525439721;
    uint256 constant STORECODE = 22222914118402840058098929392622446291855832215959547249351194445714272466276;
    uint256 constant REFPRICE = 1 ether;
    uint256 constant EXTRA = 2;
    uint8 constant REFERALDISCOUNT = 10;

    mapping(address => address payable[]) debtAddresses;
    mapping(address => uint256[]) debtAmount;

    mapping(address => uint256) referal;
    mapping(address => address payable) referalOwner;
    mapping(address => mapping(address => bool)) referalGivers;

    mapping(uint256 => bool) isRefundRequested;

    mapping(address => mapping(Role => mapping(uint256 => Product))) products;
    mapping(address => mapping(Role => string[])) productsTitles;
    mapping(address => mapping(Role => mapping(uint256 => uint256))) productsCount;
    mapping(address => mapping(Role => mapping(uint256 => uint256[]))) productsCost;
    mapping(address => mapping(Role => mapping(uint256 => uint256[]))) productionTimes;
    mapping(address => mapping(Role => mapping(uint256 => uint32[]))) storageLifeDays;

    mapping(address => mapping(Role => User)) addressAndRoleToUser;
    mapping(address => Role) currentRole;
    mapping(address => Role[]) userRoles;
    mapping(address => bool) signedIn;
    mapping(address => uint256[]) usersPurchases;
    
    event refundApproved(uint256 id);
    event refundRejected(uint256 id);
    event roleChanged(address addr);

    error NotEnoughFunds(uint256 available, uint256 required);
    error UserDoesNotExists(address addr);
    error ProductDoesNotExists(string title);
    error RoleNotSelected();
    error InvalidRole(string role);
    error PermissionDenied();

    modifier registered {
        if (!addressAndRoleToUser[msg.sender][currentRole[msg.sender]].registered) {
            revert UserDoesNotExists(msg.sender);
        }
        _;
    }

    modifier onlyOwner {
        require (msg.sender == owner, "You aren't the owner");
        _;
    }

    modifier notOwner {
        require (msg.sender != owner, "You are the owner");
        _;
    }

    modifier onlyRole(Role _role) {
        if (currentRole[msg.sender] != _role) {
            revert PermissionDenied();
        }
        _;
    }

    modifier productExists (address _owner, string memory _title) {
        bool _exists = false;
        string[] memory _titles = productsTitles[_owner][currentRole[_owner]];
        for (uint256 i = 0; i < _titles.length; i++) {
            if (generateHash(_titles[i]) == generateHash(_title)) {
                _exists = true;
                break;
            }
        }
        if (!_exists) {
            revert ProductDoesNotExists(_title);
        }
        _;
    }

    function signIn(uint16 _code) public notOwner {
        require (!signedIn[msg.sender], "You are already registered");
        uint256 hash = uint256(keccak256(abi.encodePacked(_code)));
        if (hash == SUPPLIERCODE) {
            addressAndRoleToUser[msg.sender][Role.SUPPLIER] = User(msg.sender, Role.SUPPLIER, true, 0, false, Role.SUPPLIER);
            currentRole[msg.sender] = Role.SUPPLIER;
            userRoles[msg.sender].push(Role.SUPPLIER);
            suppliers.push(msg.sender);
        } else if (hash == STORECODE) {
            addressAndRoleToUser[msg.sender][Role.STORE] = User(msg.sender, Role.STORE, true, 0, false, Role.STORE);
            currentRole[msg.sender] = Role.STORE;
            userRoles[msg.sender].push(Role.STORE);
            stores.push(msg.sender);
        } else if (_code == 0) {
            addressAndRoleToUser[msg.sender][Role.USER] = User(msg.sender, Role.USER, true, 0, false, Role.USER);
            currentRole[msg.sender] = Role.USER;
            userRoles[msg.sender].push(Role.USER);
            users.push(msg.sender);
        }
        signedIn[msg.sender] = true;
    }

    function generateHash (string memory _text) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_text)));
    }

    function generateHash (string memory _text, uint256 _production_date, uint32 _storage_life, uint256 _cost) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_text, _production_date, _storage_life, _cost)));
    }

    function removeProductTitle(address _owner, string memory _title) private {
        uint256 i = 0;
        string[] storage _titles = productsTitles[_owner][currentRole[_owner]];
        bytes32 _titleHash = keccak256(abi.encodePacked(_title));
        for (; i < _titles.length; i++) {
            if (keccak256(abi.encodePacked(_titles[i])) == _titleHash) {
                for (; i < _titles.length - 1; i++) {
                    _titles[i] = _titles[i + 1];
                }
                _titles.pop();
                break;
            }
        }
    }

    function addProduct(string memory _title, uint256 _cost_wei, uint256 _amount, uint32 _storage_life) public onlyRole(Role.SUPPLIER) {
        require (generateHash(_title) != generateHash(""), "The product must have a title");
        require (_cost_wei > 0, "The product must have a price greater than 0");
        require (_amount > 0, "The product must have a amount greater than 0");
        require (_storage_life > 0, "The product must have a storage life greater than 0 days");
        
        uint256 _currentDay = block.timestamp - block.timestamp % 1 days;
        uint256 _hashProduct = generateHash(_title, _currentDay, _storage_life, _cost_wei);

        if (products[msg.sender][currentRole[msg.sender]][_hashProduct].cost_wei > 0) 
        {
            products[msg.sender][currentRole[msg.sender]][_hashProduct].amount += _amount;
        } else {
            uint256 _hashTitle = generateHash(_title);
            products[msg.sender][currentRole[msg.sender]][_hashProduct] = Product(_title, _cost_wei, _amount, _currentDay, _storage_life, Role.SUPPLIER);
            productsTitles[msg.sender][currentRole[msg.sender]].push(_title);
            productsCost[msg.sender][currentRole[msg.sender]][_hashTitle].push(_cost_wei);
            productionTimes[msg.sender][currentRole[msg.sender]][_hashTitle].push(_currentDay);
            storageLifeDays[msg.sender][currentRole[msg.sender]][_hashTitle].push(_storage_life);
            productsCount[msg.sender][currentRole[msg.sender]][_hashTitle]++;
        }
    }

    function randomNumber(uint32 _storage_life) private view returns (uint32) {
        return uint32( ( uint256( keccak256(abi.encodePacked(block.timestamp)) ) % ((_storage_life * 2) * 1 days) ) / 1 days);
    }

    function showHistory() public view returns (Record[] memory) {
        return history;
    }

    function giveDiscount(address _target) public registered {
        require (msg.sender != _target, "You can't give a discount to yourself");
        require (addressAndRoleToUser[_target][currentRole[_target]].role == Role.USER, "The discount can only be given by the user");
        require (!referalGivers[msg.sender][_target], "You have already given a discount to this user");
        require (referal[_target] == 0, "This user already has a discount");
        uint256 _code = uint256(keccak256(abi.encodePacked(_target, block.timestamp, msg.sender)));
        referalGivers[msg.sender][_target] = true;
        referal[_target] = _code;
        referalOwner[_target] = payable(msg.sender);
        console.log("Referral code:", _code);
    }

    function getDiscount(uint256 _code) public onlyRole(Role.USER) {
        require (referal[msg.sender] == _code, "Invalid code");
        Role _role = currentRole[msg.sender];
        require (addressAndRoleToUser[msg.sender][_role].discount == 0, "You have already activated this code");
        addressAndRoleToUser[msg.sender][_role].discount = REFERALDISCOUNT;
    }

    function addCredit() private registered {
        referal[msg.sender] = 0;
        addressAndRoleToUser[msg.sender][currentRole[msg.sender]].discount = 0;
        credits.push(referalOwner[msg.sender]);
    }

    function showCredits() public view onlyOwner returns (address payable[] memory) {
        return credits;
    }

    function showCreditsDebt() public view onlyOwner returns (uint256) {
        return credits.length * REFPRICE;
    }

    function showSuppliers() public view onlyRole(Role.STORE) returns (address[] memory) {
        return suppliers;
    }

    function showStores() public view returns (address[] memory) {
        return stores;
    }

    function showUsers() public view returns (address[] memory) {
        return users;
    }

    function removeCreditsElement (uint256 _index) private {
        for (uint256 i = _index; i < credits.length; i++) {
            credits[i] = credits[i + 1];
        }
        credits.pop();
    }

    function payOffReferal(uint256 _id) public payable onlyOwner {
        if (msg.value < REFPRICE) {
            revert NotEnoughFunds({
                available: msg.value,
                required: REFPRICE
            });
        }
        require (_id < credits.length, "This credit doesn't exist");
        credits[_id].transfer(REFPRICE);
        payable(msg.sender).transfer(address(this).balance);
        removeCreditsElement(_id);
    }

    function payOffReferals() public payable onlyOwner {
        uint256 _debt = showCreditsDebt();
        if (msg.value < _debt) {
            revert NotEnoughFunds({
                available: msg.value,
                required: _debt
            });
        }
        require (credits.length > 0, "Credits list is empty");
        for (uint256 i = credits.length - 1; i > 0; i--) {
            credits[i].transfer(REFPRICE);
            credits.pop();
        }
        credits[0].transfer(REFPRICE);
        credits.pop();
        payable(msg.sender).transfer(address(this).balance);
    }

    function checkDebts() public view onlyRole(Role.STORE) returns (uint256) {
        return debtAddresses[msg.sender].length;
    }

    function showDebtAddresses() public view onlyRole(Role.STORE) returns (address payable[] memory) {
        return debtAddresses[msg.sender];
    }

    function showDebtSum() public view onlyRole(Role.STORE) returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < debtAmount[msg.sender].length; i++) {
            sum += debtAmount[msg.sender][i];
        }
        return sum;
    }

    function payOffDebt (uint256 _id) public payable onlyRole(Role.STORE) {
        require (_id < debtAddresses[msg.sender].length, "This debt doesn't exist");
        uint256 _debt = debtAmount[msg.sender][_id];
        if (msg.value < _debt) {
            revert NotEnoughFunds({
                available: msg.value,
                required: _debt
            });
        }
        debtAddresses[msg.sender][_id].transfer(_debt);
        payable(msg.sender).transfer(address(this).balance);
    }

    function payOffDebts () public payable onlyRole(Role.STORE) {
        uint256 _debts = checkDebts();
        require (_debts > 0, "Debts list is empty");
        uint256 _debt = 0;
        for (uint256 i = 0; i < _debts; i++) {
            _debt += debtAmount[msg.sender][i];
        }

        if (msg.value < _debt) {
            revert NotEnoughFunds({
                available: msg.value,
                required: _debt
            });
        }

        for (uint256 i = _debts - 1; i > 0; i--) {
            debtAddresses[msg.sender][i].transfer(debtAmount[msg.sender][i]);
            debtAddresses[msg.sender].pop();
            debtAmount[msg.sender].pop();
        }
        debtAddresses[msg.sender][0].transfer(debtAmount[msg.sender][0]);
        debtAddresses[msg.sender].pop();
        debtAmount[msg.sender].pop();
        payable(msg.sender).transfer(address(this).balance);
    }

    function refund(uint256 _id) public onlyOwner {
        require (isRefundRequested[_id], "The request has not been sent yet");
        Record memory record = history[_id];
        require (!record.refunded && !record.refund_rejected, "The request has already been processed");
        if (record.storage_life_days < record.rand_nonce) {
            record.refunded = true;
            debtAmount[record.seller].push(record.cost_wei * record.amount);
            debtAddresses[record.seller].push(record.buyer);
            emit refundApproved(_id);
        } else {
            record.refund_rejected = true;
            emit refundRejected(_id);
        }
    }

    function showRefundRequests() public view onlyOwner returns (uint256[] memory) {
        return refundRequests;
    }

    function showRefundRequestsTime() public view onlyOwner returns (uint256[] memory) {
        return refundRequestsTime;
    }

    function showChangeRoleRequests() public view onlyOwner returns (address[] memory) {
        return changeRoleRequests;
    }

    function requestChangeRole(string memory _role) public registered notOwner {
        Role _currentRole = currentRole[msg.sender];
        require (!addressAndRoleToUser[msg.sender][_currentRole].requestedRoleChange, "You have already sent a request to change the role");
        uint256 _hashRole = generateHash(_role);
        if (_hashRole == generateHash("")) {
            revert RoleNotSelected();
        } else if (_hashRole == generateHash("SUPPLIER")) {
            addressAndRoleToUser[msg.sender][_currentRole].changeRoleTo = Role.SUPPLIER;
        } else if (_hashRole == generateHash("STORE")) {
            addressAndRoleToUser[msg.sender][_currentRole].changeRoleTo = Role.STORE;
        } else if (_hashRole == generateHash("USER")) {
            addressAndRoleToUser[msg.sender][_currentRole].changeRoleTo = Role.USER;
        } else {
            revert InvalidRole(_role);
        }
        addressAndRoleToUser[msg.sender][_currentRole].requestedRoleChange = true;
        changeRoleRequests.push(msg.sender);
    }

    function removeChangeRoleRequest(uint256 _id) private {
        for (; _id < changeRoleRequests.length - 1; _id++) {
            changeRoleRequests[_id] = changeRoleRequests[_id + 1];
        }
        changeRoleRequests.pop();
    }

    function changeRole(uint256 _id) public onlyOwner {
        address _target = changeRoleRequests[_id];
        Role _role = currentRole[_target];
        User memory _user = addressAndRoleToUser[_target][_role];
        addressAndRoleToUser[_target][_role].changeRoleTo = currentRole[_target];
        addressAndRoleToUser[_target][_role].requestedRoleChange = false;
        Role _wish = _user.changeRoleTo;
        Role[] memory _roles = userRoles[_target];
        bool _isNewRole = true;
        for (uint8 i = 0; i < _roles.length; i++) {
            if (_roles[i] == _wish) {
                _isNewRole = false;
                break;
            }
        }
        if (_isNewRole) {
            addressAndRoleToUser[_target][_wish] = User(_target, _wish, true, 0, false, _wish);
            if (_wish == Role.SUPPLIER) {
                suppliers.push(_target);
            } else if (_wish == Role.STORE) {
                stores.push(_target);
            } else {
                users.push(_target);
            }
        }
        currentRole[_target] = _wish;
        removeChangeRoleRequest(_id);
        emit roleChanged(_target);
    }

    function incProduct(string memory _title, uint256 _cost_wei, uint256 _amount, uint256 _production_date, uint32 _storage_life) private {
        uint256 _hashProduct = generateHash(_title, _production_date, _storage_life, _cost_wei);
        if (products[msg.sender][currentRole[msg.sender]][_hashProduct].cost_wei > 0) {
            products[msg.sender][currentRole[msg.sender]][_hashProduct].amount += _amount;
        } else {
            uint256 _hashTitle = generateHash(_title);
            products[msg.sender][currentRole[msg.sender]][_hashProduct] = Product(_title, _cost_wei, _amount, _production_date, _storage_life, currentRole[msg.sender]);
            productsTitles[msg.sender][currentRole[msg.sender]].push(_title);
            productsCost[msg.sender][currentRole[msg.sender]][_hashTitle].push(_cost_wei);
            productionTimes[msg.sender][currentRole[msg.sender]][_hashTitle].push(_production_date);
            storageLifeDays[msg.sender][currentRole[msg.sender]][_hashTitle].push(_storage_life);
            productsCount[msg.sender][currentRole[msg.sender]][_hashTitle]++;
        }
    }

    function decProduct(string memory _title, address _owner, uint256 _amount, uint256 _production_date, uint32 _storage_life, uint256 _cost_wei) private {
        uint256 _hashProduct = generateHash(_title, _production_date, _storage_life, _cost_wei);
        products[_owner][currentRole[_owner]][_hashProduct].amount -= _amount;
        if (products[_owner][currentRole[_owner]][_hashProduct].amount == 0) {
            uint256 _hashTitle = generateHash(_title);
            delete products[_owner][currentRole[_owner]][_hashProduct];
            removeProductTitle(_owner, _title);
            productsCost[_owner][currentRole[_owner]][_hashTitle].pop();
            productionTimes[_owner][currentRole[_owner]][_hashTitle].pop();
            storageLifeDays[_owner][currentRole[_owner]][_hashTitle].pop();
            productsCount[_owner][currentRole[_owner]][_hashTitle]--;
        }
    }

    function buyProducts (address payable _seller, string memory _title, uint256 _productHash, uint256 _amount) public payable registered {
        User memory _buyerUser = addressAndRoleToUser[msg.sender][currentRole[msg.sender]];
        User memory _sellerUser = addressAndRoleToUser[_seller][currentRole[_seller]];
        require (msg.sender != _seller, "You can't buy a product from yourself");
        require (_buyerUser.role != Role.SUPPLIER, "The supplier cannot buy products from stores or users");
        require (_buyerUser.role != Role.STORE || _sellerUser.role != Role.USER, "The store cannot buy products from users");
        require (_buyerUser.role != Role.USER || _sellerUser.role != Role.SUPPLIER, "The user cannot buy products from suppliers");
        Product memory product = products[_seller][currentRole[_seller]][_productHash];
        if (product.cost_wei <= 0) {
            revert ProductDoesNotExists(_title);
        }
        require (_amount > 0, "You can buy at least 1 product");
        require (product.amount >= _amount, "There is no such quantity of products in stock");
        uint256 _totalCost = product.cost_wei * _amount / 100 * (100 - _buyerUser.discount);
        if (msg.value < _totalCost) {
            revert NotEnoughFunds({
                available: msg.value,
                required: _totalCost
            });
        }

        // Transfer
        _seller.transfer(_totalCost);
        payable(msg.sender).transfer(address(this).balance);
        decProduct(
            product.title, 
            _seller, 
            _amount, 
            product.production_date, 
            product.storage_life_days,
            product.cost_wei
        );

        if (_buyerUser.role == Role.STORE) {
            incProduct(
                product.title, 
                product.cost_wei * EXTRA, // Extra charge
                _amount, 
                product.production_date, 
                product.storage_life_days
            ); 
        } else {
            incProduct(
                product.title, 
                product.cost_wei, 
                product.amount, 
                product.production_date, 
                product.storage_life_days
            );
        }

        // Referal
        if (referal[msg.sender] != 0) {
            addCredit();
        }

        uint32 _randNonce = randomNumber(product.storage_life_days);

        console.log("Storage life days:", product.storage_life_days);
        console.log("Random nonce:", _randNonce);

        // Writing to history
        Record memory record = Record (
            payable(msg.sender), 
            _seller, 
            product.title, 
            product.cost_wei, 
            _amount, 
            product.production_date, 
            product.storage_life_days, 
            _randNonce, 
            false, 
            false
        );
        history.push(record);
        usersPurchases[msg.sender].push(history.length - 1);
    }
    
    function requestRefund(uint256 _purchaseId) public registered {
        require (!isRefundRequested[usersPurchases[msg.sender][_purchaseId]], "The request has already been sent");
        require(currentRole[msg.sender] != Role.SUPPLIER, "A supplier cannot send a refund request");
        uint256 _id = usersPurchases[msg.sender][_purchaseId];
        refundRequests.push(_id);
        isRefundRequested[_id] = true;
        refundRequestsTime.push(block.timestamp);
    }

    function showProductsTitles(address _owner) public view returns (string[] memory) {
        return productsTitles[_owner][currentRole[_owner]];
    }

    function getProductsHashesByTitle(address _owner, string memory _productTitle) public view productExists(_owner, _productTitle) returns (uint256[] memory) {
        uint256 hashTitle = generateHash(_productTitle);
        uint256 _count = productsCount[_owner][currentRole[_owner]][hashTitle];
        uint256[] memory _costs = productsCost[_owner][currentRole[_owner]][hashTitle];
        uint256[] memory _productionTimes = productionTimes[_owner][currentRole[_owner]][hashTitle];
        uint32[] memory _storageLifeDays = storageLifeDays[_owner][currentRole[_owner]][hashTitle];
        uint256[] memory _products = new uint256[](_count);
        for (uint256 i = 0; i < _count; i++) {
            _products[i] = generateHash(_productTitle, _productionTimes[i], _storageLifeDays[i], _costs[i]);
        }
        return _products;
    }

    function showProduct(address _owner, string memory _title) public view returns (Product[] memory) {
        uint256[] memory _productHashes = getProductsHashesByTitle(_owner, _title);
        uint256 _count = _productHashes.length;
        Product[] memory _products = new Product[](_count);
        for (uint256 i = 0; i < _count; i++) {
            _products[i] = products[_owner][currentRole[_owner]][_productHashes[i]];
        }
        return _products;
    }

    function showProducts(address _owner) public view returns (Product[] memory) {
        string[] memory _titles = productsTitles[_owner][currentRole[_owner]];
        uint256 _titlesLength = _titles.length;
        uint256 _totalCount = 0;
        uint256[][] memory _productsHashes = new uint256[][](_titlesLength);
        for (uint256 i = 0; i < _titlesLength; i++) {
            uint256[] memory _productHashes = getProductsHashesByTitle(_owner, _titles[i]);
            _totalCount += _productHashes.length;
            _productsHashes[i] = _productHashes;
        }

        Product[] memory _products = new Product[](_totalCount);
        _totalCount = 0;
        for (uint256 i = 0; i < _titlesLength; i++) {
            uint256[] memory _hashes = _productsHashes[i];
            for (uint256 j = 0; j < _hashes.length; j++) {
                _products[_totalCount++] = products[_owner][currentRole[_owner]][_hashes[j]];
            }
        }
        return _products;
    }

    function showProfile() public view registered returns (User memory) {
        return addressAndRoleToUser[msg.sender][currentRole[msg.sender]];
    }
}