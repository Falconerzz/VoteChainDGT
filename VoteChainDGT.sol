// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./VoteChainDGT_Config.sol";
import "./VoteChainDGT_StudentIdValidator.sol";

contract VoteChainDGT is VoteChainDGT_Config, VoteChainDGT_StudentIdValidator {
    // Events
    event CandidateAdded(uint8 candidateId, string partyName);
    event CandidateRemoved(uint8 candidatePartyNumber, string partyName);
    event VoterRegistered(address voterAccount, string studentId);
    event VoteCast(address voterAccount, uint8 candidateId);
    event VotingPeriodSet(uint256 startTimestamp, uint256 endTimestamp);

    // Structs
    struct Candidate {
        uint8 candidateId;
        uint8 candidatePartyNumber;
        string candidatePartyName;
        string candidatePolicy;

        string candidateTitle;
        string candidateFirstName;
        string candidateLastName;
        string candidateNickname;
        uint8 candidateAge;
        string candidateBranch;
        string candidateStudentId;
        uint256 totalVotes;
        uint256 timeAdded;
    }

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        bool hasVotingToken;
        string studentId;
        string voterTitle;
        string voterFirstName;
        string voterLastName;
        string voterBranch;
    }

    struct PartyVoteResult {
        uint8 partyNumber;
        uint256 voteCount;
    }

    uint8 public totalCandidates = 0;
    uint32 public totalRegisteredVoters = 0;
    uint32 public totalVotesCast = 0;
    uint32 public totalRegisteredVotersWhoVoted = 0;

    mapping(uint8 => Candidate) private candidates;
    mapping(address => Voter) private voters;
    mapping(string => bool) private partyNameUsed;
    mapping(string => bool) private studentIdsUsed;
    mapping(string => bool) private candidateStudentIdsUsed;

    uint256 public votingStartTime;
    uint256 public votingEndTime;

    // Admin addresses manually managed
    address[] public adminAddresses;

    // ตัวแปรเก็บแอดมินจำนวน (ถ้าต้องการ)
    uint16 public totalAdmins = 0;

    // เพิ่มแอดมินคนแรกตอน deploy
    constructor() {
        adminAddresses.push(msg.sender);
        totalAdmins = 1;
    }

    // ตรวจสอบว่าเป็นแอดมิน (manual check)
    modifier onlyAdmin() {
        bool adminFound = false; // เปลี่ยนชื่อตัวแปรไม่ให้ซ้ำกับฟังก์ชัน
        for(uint i = 0; i < adminAddresses.length; i++) {
            if(adminAddresses[i] == msg.sender) {
                adminFound = true;
                break;
            }
        }
        require(adminFound, "Caller is not an admin");
        _;
    }

    // ลบแอดมิน (ฟังก์ชันเสริมถ้าต้องการ)
    function removeAdmin(address adminToRemove) external onlyAdmin {
        for (uint i = 0; i < adminAddresses.length; i++) {
            if (adminAddresses[i] == adminToRemove) {
                adminAddresses[i] = adminAddresses[adminAddresses.length - 1];
                adminAddresses.pop();
                totalAdmins--;
                break;
            }
        }
    }

    function setVotingPeriod(uint256 startTimestamp, uint256 endTimestamp) external onlyAdmin {
        require(startTimestamp < endTimestamp, "Start must be before end");
        votingStartTime = startTimestamp;
        votingEndTime = endTimestamp;
        emit VotingPeriodSet(startTimestamp, endTimestamp);
    }

    function addCandidate(
        uint8 candidateId,
        uint8 candidatePartyNumber,
        string calldata candidatePartyName,
        string calldata candidatePolicy,
        string calldata candidateTitle,
        string calldata candidateFirstName,
        string calldata candidateLastName,
        string calldata candidateNickname,
        uint8 candidateAge,
        string calldata candidateBranch,
        string calldata candidateStudentId
    ) external onlyAdmin {
        require(block.timestamp < votingStartTime || votingStartTime == 0, "Cannot add candidates during voting period");
        require(isValidStudentId(candidateStudentId), "Invalid candidate student ID format");
        require(!partyNameUsed[candidatePartyName], "Party name already used");
        require(candidateId > 0 && candidateId <= MAX_CANDIDATE_ID, "ID must be between 1 and MAX_CANDIDATE_ID");
        require(candidatePartyNumber > 0 && candidatePartyNumber <= MAX_PARTY_NUMBER, "Party number must be between 1 and MAX_PARTY_NUMBER");
        require(candidates[candidateId].candidateId == 0, "ID already taken");
        require(candidates[candidatePartyNumber].candidatePartyNumber == 0, "Party number already taken");
        require(!candidateStudentIdsUsed[candidateStudentId], "Candidate Student ID already used");
        require(
            keccak256(abi.encodePacked(candidateBranch)) == keccak256(abi.encodePacked(BRANCH_DT)) ||
            keccak256(abi.encodePacked(candidateBranch)) == keccak256(abi.encodePacked(BRANCH_DC)),
            "candidateBranch must be DT or DC"
        );

        Candidate memory newCandidate = Candidate({
            candidateId: candidateId,
            candidatePartyNumber: candidatePartyNumber,
            candidatePartyName: candidatePartyName,
            candidatePolicy: candidatePolicy,
            candidateTitle: candidateTitle,
            candidateFirstName: candidateFirstName,
            candidateLastName: candidateLastName,
            candidateNickname: candidateNickname,
            candidateAge: candidateAge,
            candidateBranch: candidateBranch,
            candidateStudentId: candidateStudentId,
            totalVotes: 0,
            timeAdded: block.timestamp
        });

        candidates[candidateId] = newCandidate;
        partyNameUsed[candidatePartyName] = true;
        candidateStudentIdsUsed[candidateStudentId] = true;

        if (candidateId > totalCandidates) {
            totalCandidates = candidateId;
        }

        emit CandidateAdded(candidateId, candidatePartyName);
    }

    function removeCandidateByPartyNumber(uint8 partyNumber) external onlyAdmin {
        Candidate storage candidate = candidates[partyNumber];
        require(candidate.candidateId != 0, "Candidate not found");

        partyNameUsed[candidate.candidatePartyName] = false;
        candidateStudentIdsUsed[candidate.candidateStudentId] = false;

        delete candidates[partyNumber];

        if (candidate.candidateId == totalCandidates) {
            totalCandidates--;
        }

        emit CandidateRemoved(partyNumber, candidate.candidatePartyName);
    }

    function registerVoter(
        string calldata studentId,
        string calldata voterTitle,
        string calldata voterFirstName,
        string calldata voterLastName,
        string calldata voterBranch
    ) external {
        require(block.timestamp >= votingStartTime && block.timestamp <= votingEndTime, "Registration is only allowed during voting period");
        require(!isAdmin(msg.sender), "Admins cannot register as voters");

        require(isValidStudentId(studentId), "Invalid student ID format");
        require(!studentIdsUsed[studentId], "Student ID already registered");
        require(!candidateStudentIdsUsed[studentId], "Candidate Student ID cannot register as voter");
        require(!voters[msg.sender].isRegistered, "This account is already registered");

        voters[msg.sender] = Voter({
            isRegistered: true,
            hasVoted: false,
            hasVotingToken: true,
            studentId: studentId,
            voterTitle: voterTitle,
            voterFirstName: voterFirstName,
            voterLastName: voterLastName,
            voterBranch: voterBranch
        });
        totalRegisteredVoters++;

        studentIdsUsed[studentId] = true;

        emit VoterRegistered(msg.sender, studentId);
    }

    function vote(
        string calldata studentId,
        uint8 candidatePartyNumber
    ) external {
        require(block.timestamp >= votingStartTime && block.timestamp <= votingEndTime, "Voting is closed");

        Voter storage voterData = voters[msg.sender];
        require(voterData.isRegistered, "Not registered");
        require(keccak256(abi.encodePacked(voterData.studentId)) == keccak256(abi.encodePacked(studentId)), "Student ID mismatch");
        require(!voterData.hasVoted, "Already voted");
        require(voterData.hasVotingToken, "No voting token");

        Candidate storage candidateData = candidates[candidatePartyNumber];
        require(candidateData.candidateId != 0, "Bad candidate");

        voterData.hasVoted = true;
        voterData.hasVotingToken = false;
        candidateData.totalVotes++;
        totalVotesCast++;
        totalRegisteredVotersWhoVoted++;

        emit VoteCast(msg.sender, candidatePartyNumber);
    }

    function getAllCandidates() external view returns (uint8, Candidate[] memory) {
        Candidate[] memory candidateList = new Candidate[](totalCandidates);
        uint8 index = 0;

        for (uint8 i = 1; i <= totalCandidates; i++) {
            if (candidates[i].candidateId != 0) {
                candidateList[index] = candidates[i];
                index++;
            }
        }
        return (totalCandidates, candidateList);
    }

    function getCandidateByPartyNumber(uint8 partyNumber)
        external
        view
        returns (
            uint8 candidateId,
            string memory candidateTitle,
            string memory candidateFirstName,
            string memory candidateLastName,
            string memory candidateNickname,
            uint8 candidateAge,
            string memory candidateBranch,
            string memory candidateStudentId,
            uint8 candidatePartyNumber,
            string memory candidatePartyName,
            string memory candidatePolicy,
            uint256 timeAdded
        )
    {
        Candidate storage candidate = candidates[partyNumber];
        require(candidate.candidateId != 0, "Candidate not found");

        return (
            candidate.candidateId,
            candidate.candidateTitle,
            candidate.candidateFirstName,
            candidate.candidateLastName,
            candidate.candidateNickname,
            candidate.candidateAge,
            candidate.candidateBranch,
            candidate.candidateStudentId,
            candidate.candidatePartyNumber,
            candidate.candidatePartyName,
            candidate.candidatePolicy,
            candidate.timeAdded
        );
    }

    function getAllPartyVotes() external view returns (PartyVoteResult[] memory partyVoteResults) {
        require(block.timestamp > votingEndTime, "Election not ended yet");
        PartyVoteResult[] memory voteList = new PartyVoteResult[](totalCandidates);
        uint8 index = 0;

        for (uint8 i = 1; i <= totalCandidates; i++) {
            if (candidates[i].candidateId != 0) {
                voteList[index] = PartyVoteResult({
                    partyNumber: candidates[i].candidatePartyNumber,
                    voteCount: candidates[i].totalVotes
                });
                index++;
            }
        }

        return voteList;
    }

    function getWinner() external view returns (uint8 partyNumber, string memory partyName, string memory candidatePolicy, uint256 votes) {
        require(block.timestamp > votingEndTime, "Election not ended yet");

        uint256 maxVotes = 0;
        uint8 winnerId = 0;

        for (uint8 i = 1; i <= totalCandidates; ++i) {
            uint256 vc = candidates[i].totalVotes;
            if (vc > maxVotes) {
                maxVotes = vc;
                winnerId = i;
            }
        }

        require(winnerId != 0, "No winner found");

        partyNumber = candidates[winnerId].candidatePartyNumber;
        partyName = candidates[winnerId].candidatePartyName;
        candidatePolicy = candidates[winnerId].candidatePolicy;
        votes = candidates[winnerId].totalVotes;
    }

    function getAdmins() external view returns (address[] memory) {
        return adminAddresses;
    }

    function getElectionSummary()
        external
        view
        returns (
            uint16 adminCount,
            uint8 candidateCount,
            uint32 registeredVoterCount,
            uint32 totalVoteCount,
            uint32 registeredButNotVotedCount
        )
    {
        adminCount = totalAdmins;
        candidateCount = totalCandidates;
        registeredVoterCount = totalRegisteredVoters;
        totalVoteCount = totalVotesCast;
        registeredButNotVotedCount = totalRegisteredVoters - totalRegisteredVotersWhoVoted;
    }

    function getStudentIdByAccount(address account) external view returns (string memory) {
        Voter storage voterData = voters[account];
        require(voterData.isRegistered, "Account not registered as voter");
        return voterData.studentId;
    }

    // helper internal function to check admin
    function isAdmin(address user) internal view returns (bool) {
        for(uint i = 0; i < adminAddresses.length; i++) {
            if(adminAddresses[i] == user) {
                return true;
            }
        }
        return false;
    }
}
