// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

contract fund{

    address public managerAddr = msg.sender;
    string[] public fundSectors; // the target sectors of the fund

    bool public notFundedCompany;
    bool public inTargetSectors;

    enum ProjectState {ineligible, accepted, rejected, approved, closed}

    address[] public fundedCompanies;
    address[] public fundedProjects;

    struct project {
        address projectAddr;
        address projectOwnerAddr;
        bool submitted;
        ProjectState projectState;
    }

    mapping(address => project) public portfolioStatus;

    // Check if a Sector is already in the fundSectors List.
    function addFundSectors(string memory _sector) public {
        require(msg.sender == managerAddr, "Only the fund manager can define target sectors.");

        for (uint i = 0; i < fundSectors.length; i++) {
            /*
            String comparison cannot be done with == or != in Solidity. 
            It is because Solidity do not support operator natively. 
            We need to hash string to byte array to compare value in Solidity.
            */
            if (keccak256(abi.encodePacked(fundSectors[i])) == keccak256(abi.encodePacked(_sector))) {
                // revert(string memory reason) abort execution and revert state changes, providing an explanatory string.
                revert("The sector is already in the list!");
            }
        }
        fundSectors.push(_sector);
    }

    // Set investment criteria.
    function setCriteria(bool _notFundedCompany, bool _inTargetSectors) public {
        require(msg.sender == managerAddr, "Only the fund manager can set the criteria.");

        notFundedCompany = _notFundedCompany;
        inTargetSectors = _inTargetSectors;
    }

    // Check if a proposal has already funded by the fund.
    function isDuplicateApplication(address _projectAddr) public view returns (bool) {
        for (uint i = 0; i < fundedProjects.length; i++) {
            if (fundedProjects[i] == _projectAddr) {
                return true;
            }
        }
        return false;
    }

    // Check if a company has already received funding from the fund.
    function isPortfolioCompanies(address _projectOwnerAddr) public view returns (bool) {
        for (uint i = 0; i < fundedCompanies.length; i++) {
            if (fundedCompanies[i] == _projectOwnerAddr) {
                return true;
            }
        }
        return false;
    }

    // Check if a proposal is in the target sectors of the fund.
    function isTargetSector(string[] memory _projectSectors) public view returns (bool) {
        for (uint i = 0; i < fundSectors.length; i++){
            for (uint j = 0; j < _projectSectors.length; j++){
                /*
                String comparison cannot be done with == or != in Solidity. 
                It is because Solidity do not support operator natively. 
                We need to hash string to byte array to compare value in Solidity.
                */                
                if (keccak256(abi.encodePacked(fundSectors[i])) == keccak256(abi.encodePacked(_projectSectors[j]))) {
                    return true;
                }
            }
        }
        return false;
    }

    function acceptProposal(address _projectOwnerAddr, string[] memory _projectSectors) external returns(bool) {

        if (portfolioStatus[msg.sender].submitted == true) {
            revert ("Duplicate Application!");
        }

            
        if (notFundedCompany == true){
            if (isPortfolioCompanies(_projectOwnerAddr) == true){
                revert ("The company has already received funding from the fund.");
            }
        }
        
        if (inTargetSectors == true){
            if (isTargetSector(_projectSectors) == false) {
                revert ("The proposal is not in our target sectors!");
            }
        }

        portfolioStatus[msg.sender].projectAddr = msg.sender;
        portfolioStatus[msg.sender].projectOwnerAddr = _projectOwnerAddr;
        portfolioStatus[msg.sender].submitted = true;
        portfolioStatus[msg.sender].projectState = ProjectState.accepted;

        return true;
    }

    function approveProposal(address _projectAddr, bool _approved) external {
        if (_approved == true)
        {
            portfolioStatus[_projectAddr].projectState = ProjectState.approved;
            fundedProjects.push(portfolioStatus[_projectAddr].projectAddr);
            fundedCompanies.push(portfolioStatus[_projectAddr].projectOwnerAddr);
        }
        else if (_approved == false)
        {
            portfolioStatus[_projectAddr].projectState = ProjectState.rejected;
        }
    }

    function closeProject(address _projectAddr) external {
        portfolioStatus[_projectAddr].projectState = ProjectState.closed;
    }
}
