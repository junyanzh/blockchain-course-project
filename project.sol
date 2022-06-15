// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface interFund {
    function managerAddr() external view returns (address);
    function acceptProposal(address _projectOwnerAddr, string[] memory _projectSectors) external returns (bool);
    function approveProposal(address _projectAddr, bool _approved) external;
    function closeProject(address _projectAddr) external;
}

contract project {
    address public fundAddr;  
    address public fundManagerAddr; 
    address payable public ownerAddr;
    address public projectAddr;

    string[] public projectSectors; // The target sectors of the project.
    uint256 public totalSectors = 0;

    // enum ProjectState {initiated, planned, rejected, submitted, approved, closed}
    enum TaskState {planned, revised, funded, submitted, resubmitted, rejected, approved, released}
    enum SubmissionState {none, on_time, delayed}

    struct ProjectState {
        bool initiated;
        bool submitted;
        bool eligible; 
        bool rejected;
        bool revised;
        bool approved; 
        bool closed;
    }

    struct task {
        string taskCode;
        string description;
        uint256 deadline;
        uint256 value;
        uint256 submissionDate;
        SubmissionState submissionState;
        TaskState taskState; // One of the states that this task is currently in, i.e. planned, funded, started, approved, and released.
    }

    mapping(int256 => task) public projectPlan; // Store all the tasks of the project.
    int256 public totalTasks = 0; // Keep track of the total number of tasks that the project has.

    ProjectState public projectState; // The current state of the project.

    constructor () {
        ownerAddr = payable(msg.sender);
        projectAddr = address(this);
        projectState.initiated = true;
    }

    event taskAdded(string taskCode);
    event projectEligible(address fundManagerAddr);
    event projectSubmitted(address fundManagerAddr);
    event projectApproved(address fundManagerAddr);
    event projectRejected(address ownerAddr);
    event projectRevised(address fundManagerAddr);
    event taskFunded(int256 taskID);
    event taskSubmitted(int256 taskID);
    event taskApproved(int256 taskID);
    event taskRejected(int256 taskID);
    event fundsReleased(int256 taskID, uint256 valueReleased);
    event projectEnded();

    modifier onlyOwner() {
		require(msg.sender == ownerAddr);
		_;
	}

    modifier onlyFundManager() {
		require(msg.sender == fundManagerAddr);
		_;
	}

    modifier bothFundManagerProjectOwner(){
		require(msg.sender == ownerAddr || msg.sender == fundManagerAddr);
		_;	    
	}

    /*
    The inScheduleState() modifier checks if the schedule in question is in a specific state (e.g. funded). 
    This allows the functions to test if a schedule is ready to move on to the next state.
    For example, a schedule can only move on to the funded state if it is currently in the planned state.
    */
    modifier inTaskState(int256 _taskID, TaskState _state){
        require((_taskID <= totalTasks - 1) && projectPlan[_taskID].taskState == _state);
        _;
    }

    /*
    The ampleFunding() modifier checks if a task's funding is equivalent to the funding that it is supposed to receive.
    */
    modifier ampleFunding(int256 _taskID, uint256 _funding){
        require(projectPlan[_taskID].value == _funding);
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////

    // Interface with the fund.
    function connectFund(address _fund) public payable{
        fundAddr = _fund;
        fundManagerAddr = interFund(fundAddr).managerAddr();
    }

    // The project owner adds a sector to the target sectors .
    function addProjectSectors(string memory _sector) public
        onlyOwner 
    {
        require(projectState.initiated == true);

        // Check if a Sector is already in the ProjectSectors List.
        for (uint i = 0; i < projectSectors.length; i++) {
            if (keccak256(abi.encodePacked(projectSectors[i])) == keccak256(abi.encodePacked(_sector))) {
                revert("The sector is already in the list!");
            }
        }
        projectSectors.push(_sector);
        totalSectors++;
    }

    // The project owner adds a task to the project plan.
    function addTask(string memory _taskCode, string memory _description, uint256 _deadline, uint256 _value) public
        onlyOwner
    {       
        if (projectState.approved == false)
        {
            if (projectState.submitted == true && projectState.rejected == false)
            {
                revert("Please do not change the project plan after the project has been submitted.");
            }
        }
        else if (projectState.approved == true)
        {
            revert("Please do not change the project plan after the project has been approved.");
        }
        
        if (projectState.closed == true)
        {
            revert("The project has been closed");
        }

        task memory t;
        t.taskCode = _taskCode;
        t.description = _description;
        t.taskState = TaskState.planned;
        t.deadline = _deadline;
        t.value = _value;
        t.submissionState = SubmissionState.none;
        projectPlan[totalTasks] = t;
        totalTasks++;
        emit taskAdded(_taskCode);
    }

    // The project owner changes a task.
    function changeTask(int256 _taskID, string memory _taskCode, string memory _description, uint256 _deadline, uint256 _value) public
        onlyOwner
    {
        if (projectState.approved == false)
        {
            if (projectState.submitted == true && projectState.rejected == false)
            {
                revert("Please do not change the project plan after the project has been submitted.");
            }
        }
        else if (projectState.approved == true)
        {
            revert("Please do not change the project plan after the project has been approved.");
        }

        if (projectState.closed == true)
        {
            revert("The project has been closed");
        }

        require(_taskID <= totalTasks - 1);

        projectPlan[_taskID].taskCode = _taskCode;
        projectPlan[_taskID].description = _description;
        projectPlan[_taskID].deadline = _deadline;
        projectPlan[_taskID].value = _value;

        if (projectState.rejected == true)
        {
            projectPlan[_taskID].taskState = TaskState.revised;
            projectPlan[_taskID].submissionState = SubmissionState.none;
        }
        emit taskAdded(_taskCode);
    }

    // The project owner submits the proposal.
    function submitProposal() external
        onlyOwner 
    {        
        //require(projectState.planned == true, "Please complete the project plan!");
        require(totalSectors >= 1, "Please define target sectors");
        require(totalTasks >=1, "Please create a project plan!");
        require(projectState.submitted == false, "The project has been submitted.");
        require(projectState.approved == false, "The project has been approved.");
        require(projectState.closed == false, "The project has been closed");

        projectState.submitted = true;
        emit projectSubmitted(msg.sender);

        bool _accepted = interFund(fundAddr).acceptProposal(ownerAddr, projectSectors);

        if (_accepted == true) 
        {            
            projectState.eligible = true;            
            emit projectEligible(msg.sender);
        } 
    }

    // The fund manager approves the project plan.
    function approvePlan(bool _approved) public 
        onlyFundManager
    {
        require(projectState.submitted == true, "The project has not been submitted.");
        require(projectState.eligible == true, "The project is not eligible for funding.");
        require(projectState.approved == false, "The project has been approved.");
        require(projectState.closed == false, "The project has been closed.");

        if (projectState.rejected == true && projectState.revised == false)
        {
            revert("The project plan has not beem revised.");
        }

        if (_approved == true) 
        {
            projectState.approved = true;
            projectState.rejected = false;
            emit projectApproved(msg.sender);
        } 
        else if (_approved == false)
        {
            projectState.rejected = true;
            emit projectRejected(msg.sender);
        }
        interFund(fundAddr).approveProposal(projectAddr, _approved);
    }

    // The project owner changes the project plan.
    function revisePlan() public
        onlyOwner
    {
        if (projectState.submitted == false)
        {
            revert("The project has not been submitted.");
        }

        if (projectState.submitted == true && projectState.rejected == false)
        {
            revert("Please do not change the project plan after the project has been submitted.");
        }

        require(projectState.eligible == true, "The project is not eligible for funding.");
        require(projectState.approved == false, "Please do not change the project plan after the project has been approved.");
        require(projectState.closed == false, "The project has been closed");

        projectState.revised = true;
        emit projectRevised(msg.sender);
    }

    // The fund manager funds a task.
    function fundTask(int256 _taskID) public payable
        inTaskState(_taskID, TaskState.planned)
        ampleFunding(_taskID, msg.value)
        onlyFundManager
    {
        require(projectState.approved == true, "The project has not been approved");
        require(projectState.closed == false, "The project has been closed");
        projectPlan[_taskID].taskState = TaskState.funded;
        emit taskFunded(_taskID);
    }

    // The project owner submits a task.
    function submitTask(int256 _taskID) public
        onlyOwner
    {
        require(projectState.approved == true, "The project has not been approved");
        require(projectState.closed == false, "The project has been closed");
        require
        (
            (_taskID <= totalTasks - 1) && 
            (projectPlan[_taskID].taskState == TaskState.funded) || 
            (projectPlan[_taskID].taskState == TaskState.rejected)
        );

        if (projectPlan[_taskID].taskState == TaskState.rejected)
        {
            projectPlan[_taskID].taskState = TaskState.resubmitted;
        }
        else
        {
            projectPlan[_taskID].taskState = TaskState.submitted;
            emit taskSubmitted(_taskID);
        }

        projectPlan[_taskID].submissionDate = block.timestamp;
        if (projectPlan[_taskID].submissionDate >= projectPlan[_taskID].deadline)
        {
            projectPlan[_taskID].submissionState = SubmissionState.delayed;
        }
        else
        {
            projectPlan[_taskID].submissionState = SubmissionState.on_time;
        }
    }

    // The fund manager approves a task.
    function approveTask (int256 _taskID, bool _approved) external 
        onlyFundManager
    {
        require(projectState.approved == true, "The project has not been approved");
        require(projectState.closed == false, "The project has been closed");

        require
        (
            (projectPlan[_taskID].taskState == TaskState.submitted) || 
            (projectPlan[_taskID].taskState == TaskState.resubmitted)
        );

        if (_approved == true)
        {
            projectPlan[_taskID].taskState = TaskState.approved;
            emit taskApproved(_taskID);
        }
        else if (_approved == false)
        {
            projectPlan[_taskID].taskState = TaskState.rejected;
            emit taskRejected(_taskID);
        }
        
    }

    function releaseFunds(int256 _taskID) public payable
        inTaskState(_taskID, TaskState.approved) 
        onlyOwner
    {
        require(projectState.approved == true, "The project has not been approved");
        require(projectState.closed == false, "The project has been closed");
        ownerAddr.transfer(projectPlan[_taskID].value);
        projectPlan[_taskID].taskState = TaskState.released;
        emit fundsReleased(_taskID, projectPlan[_taskID].value);
    }

    function projectCompleted() public view returns(bool) {
        for (int256 i = 0; i < totalTasks; i++)
        {
            if (projectPlan[i].taskState != TaskState.released)
            {
                return false;
            }
        }
        return true;
    }

    function endProject() public
        bothFundManagerProjectOwner
    {
        require(projectCompleted() == true);
        projectState.closed = true;
        emit projectEnded();

        interFund(fundAddr).closeProject(projectAddr);
    } 
}
