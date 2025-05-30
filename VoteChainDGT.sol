// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./VoteChainDGT_Config.sol";
import "./VoteChainDGT_StudentIdValidator.sol";

contract VoteChainDGT is VoteChainDGT_Config, VoteChainDGT_StudentIdValidator {
    // Events
    event CandidateAdded(uint8 candidateId, string partyName); 
    event CandidateRemoved(uint8 candidateId, string partyName); 
    event VoterRegistered(address voterAccount, string studentId); 
    event VoteCast(address voterAccount, uint8 candidatePartyNumber); 
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
        bool exists; // Flag สำหรับเช็คว่าผู้สมัครยังอยู่ (active) หรือถูกลบแล้ว
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

    // ตัวแปรเก็บสถานะผู้สมัคร
    uint8 maxCandidateId = 0; // หมายเลขผู้สมัครสูงสุดที่เคยมี
    uint8 totalCandidates = 0; // จำนวนผู้สมัครที่ยัง active อยู่จริง

    // ตัวแปรสถิติการเลือกตั้ง
    uint32 totalRegisteredVoters = 0; 
    uint32 totalVotesCast = 0;
    uint32 totalRegisteredVotersWhoVoted = 0; 

    // Mapping เก็บข้อมูลผู้สมัครโดยใช้ candidateId เป็น key
    mapping(uint8 => Candidate) private candidates;
    // Mapping เก็บข้อมูลผู้เลือกตั้ง
    mapping(address => Voter) private voters;
    // ตรวจสอบว่าชื่อพรรคถูกใช้ไปแล้วหรือยัง
    mapping(string => bool) private partyNameUsed;
    // ตรวจสอบว่ารหัสนักศึกษาถูกใช้ไปแล้วหรือยัง สำหรับผู้ลงทะเบียนเลือกตั้ง
    mapping(string => bool) private studentIdsUsed;
    // ตรวจสอบว่ารหัสนักศึกษาผู้สมัครถูกใช้ไปแล้วหรือยัง
    mapping(string => bool) private candidateStudentIdsUsed;

    address[] private registeredVoterAddresses;

    uint256 public votingStartTime; 
    uint256 public votingEndTime; 

    address[] adminAddresses; 
    uint16 totalAdmins = 0; 

    // constructor เพิ่มแอดมินคนแรก
    constructor() {
        adminAddresses.push(msg.sender);
        totalAdmins = 1; 
    }

    // modifier ตรวจสอบสิทธิ์แอดมิน
    modifier onlyAdmin() {
        bool adminFound = false; 
        for(uint i = 0; i < adminAddresses.length; i++) {
            if(adminAddresses[i] == msg.sender) {
                adminFound = true;
                break;
            }
        }
        require(adminFound, "Caller is not an admin");
        _;
    }

    // ฟังก์ชันตั้งช่วงเวลาเลือกตั้ง และรีเซ็ตข้อมูลที่เกี่ยวข้อง
    function setVotingPeriod(uint256 startTimestamp, uint256 endTimestamp) external onlyAdmin {
        require(startTimestamp < endTimestamp, "Start must be before end");
        votingStartTime = startTimestamp; 
        votingEndTime = endTimestamp;
        emit VotingPeriodSet(startTimestamp, endTimestamp); 

        // รีเซ็ตคะแนนโหวตของผู้สมัครที่ยัง active
        for (uint8 i = 1; i <= maxCandidateId; i++) {
            if (candidates[i].exists) {
                candidates[i].totalVotes = 0;
            }
        }

        // ลบข้อมูลผู้ลงทะเบียนเลือกตั้งทั้งหมด
        for (uint i = 0; i < registeredVoterAddresses.length; i++) {
            address voterAddr = registeredVoterAddresses[i];
            if(voters[voterAddr].isRegistered) {
                studentIdsUsed[voters[voterAddr].studentId] = false;
                delete voters[voterAddr];
            }
        }
        delete registeredVoterAddresses;

        // รีเซ็ตสถิติ
        totalRegisteredVoters = 0;
        totalVotesCast = 0;
        totalRegisteredVotersWhoVoted = 0;
    }

    // ฟังก์ชันเพิ่มผู้สมัครใหม่
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
        // เงื่อนไขสำคัญ: เพิ่มผู้สมัครได้ก็ต่อเมื่อไม่อยู่ในช่วงเวลาการเลือกตั้ง
        require(block.timestamp < votingStartTime || votingStartTime == 0 || block.timestamp > votingEndTime, "Cannot add candidates during voting period");
        
        require(isValidStudentId(candidateStudentId), "Invalid candidate student ID format");
        require(candidateId > 0 && candidateId <= MAX_CANDIDATE_ID, "ID must be between 1 and MAX_CANDIDATE_ID");
        require(candidatePartyNumber > 0 && candidatePartyNumber <= MAX_PARTY_NUMBER, "Party number must be between 1 and MAX_PARTY_NUMBER");

        // ตรวจสอบว่า candidateId ยังไม่มีผู้สมัครที่ active อยู่
        require(!candidates[candidateId].exists, "Candidate ID already taken");
        // ตรวจสอบชื่อพรรคยังไม่ถูกใช้
        require(!partyNameUsed[candidatePartyName], "Party name already used");
        // ตรวจสอบรหัสนักศึกษาผู้สมัครยังไม่ถูกใช้
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
            timeAdded: block.timestamp,
            exists: true
        });

        candidates[candidateId] = newCandidate;
        partyNameUsed[candidatePartyName] = true;
        candidateStudentIdsUsed[candidateStudentId] = true;

        if (candidateId > maxCandidateId) {
            maxCandidateId = candidateId;
        }

        totalCandidates++;

        emit CandidateAdded(candidateId, candidatePartyName);
    }

    // ฟังก์ชันลบผู้สมัครโดยใช้ candidateId
    function removeCandidateByCandidateId(uint8 candidateId) external onlyAdmin {
        Candidate storage candidate = candidates[candidateId];
        require(candidate.exists, "Candidate not found");

        partyNameUsed[candidate.candidatePartyName] = false;
        candidateStudentIdsUsed[candidate.candidateStudentId] = false;

        // ล้างข้อมูลผู้สมัคร
        candidate.exists = false;
        candidate.totalVotes = 0;
        candidate.candidatePartyNumber = 0;
        candidate.candidatePartyName = "";
        candidate.candidatePolicy = "";
        candidate.candidateTitle = "";
        candidate.candidateFirstName = "";
        candidate.candidateLastName = "";
        candidate.candidateNickname = "";
        candidate.candidateAge = 0;
        candidate.candidateBranch = "";
        candidate.candidateStudentId = "";
        candidate.timeAdded = 0;

        totalCandidates--;

        emit CandidateRemoved(candidateId, candidate.candidatePartyName);
    }

    // ฟังก์ชันลงทะเบียนผู้เลือกตั้ง
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
        registeredVoterAddresses.push(msg.sender);

        emit VoterRegistered(msg.sender, studentId);
    }

    // ฟังก์ชันโหวตโดยระบุเลขพรรค (candidatePartyNumber)
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

        // หา candidateId โดยวนหา candidate ที่เลขพรรคตรงกับ candidatePartyNumber
        uint8 candidateId = 0;
        for (uint8 i = 1; i <= maxCandidateId; i++) {
            if (candidates[i].exists && candidates[i].candidatePartyNumber == candidatePartyNumber) {
                candidateId = i;
                break;
            }
        }
        require(candidateId != 0, "Bad candidate party number");

        Candidate storage candidateData = candidates[candidateId];

        voterData.hasVoted = true;
        voterData.hasVotingToken = false;
        candidateData.totalVotes++;
        totalVotesCast++;
        totalRegisteredVotersWhoVoted++;

        emit VoteCast(msg.sender, candidatePartyNumber);
    }

    // ดึงข้อมูลผู้สมัครทั้งหมด
    function getAllCandidates() external view returns (uint8, Candidate[] memory) {
        Candidate[] memory tempList = new Candidate[](totalCandidates);
        uint8 index = 0;

        for (uint8 i = 1; i <= maxCandidateId; i++) {
            if (candidates[i].exists) {
                tempList[index] = candidates[i];
                index++;
            }
        }

        Candidate[] memory candidateList = new Candidate[](index);
        for (uint8 j = 0; j < index; j++) {
            candidateList[j] = tempList[j];
        }

        return (index, candidateList);
    }

    // ฟังก์ชันค้นหาผู้สมัครจากเลขพรรค (candidatePartyNumber)
    function getCandidateByPartyNumber(uint8 partyNumber)
        external
        view
        returns (
            uint8 candidateId,
            uint8 candidatePartyNumber,
            string memory candidatePartyName,
            string memory candidatePolicy,
            string memory candidateTitle,
            string memory candidateFirstName,
            string memory candidateLastName,
            string memory candidateNickname,
            uint8 candidateAge,
            string memory candidateBranch,
            string memory candidateStudentId,
            uint256 timeAdded
        )
    {
        for (uint8 i = 1; i <= maxCandidateId; i++) {
            if (candidates[i].exists && candidates[i].candidatePartyNumber == partyNumber) {
                Candidate storage c = candidates[i];
                return (
                    c.candidateId,
                    c.candidatePartyNumber,
                    c.candidatePartyName,
                    c.candidatePolicy,
                    c.candidateTitle,
                    c.candidateFirstName,
                    c.candidateLastName,
                    c.candidateNickname,
                    c.candidateAge,
                    c.candidateBranch,
                    c.candidateStudentId,
                    c.timeAdded
                );
            }
        }
        revert("Candidate with given party number not found");
    }

    // ดึงผลโหวตทั้งหมดของพรรค
    function getAllPartyVotes() external view returns (PartyVoteResult[] memory partyVoteResults) {
        require(block.timestamp > votingEndTime, "Election not ended yet");
        PartyVoteResult[] memory voteList = new PartyVoteResult[](totalCandidates);
        uint8 index = 0;

        for (uint8 i = 1; i <= maxCandidateId; i++) {
            if (candidates[i].exists) {
                voteList[index] = PartyVoteResult({
                    partyNumber: candidates[i].candidatePartyNumber,
                    voteCount: candidates[i].totalVotes
                });
                index++;
            }
        }

        return voteList;
    }

    // หาผู้ชนะ (ผู้สมัครที่คะแนนมากที่สุด)
    function getWinner() external view returns (
        uint8 partyNumber,
        string memory partyName,
        string memory candidatePolicy,
        uint256 votes,
        bool isTie
    ) {
        require(block.timestamp > votingEndTime, "Election not ended yet");

        uint256 maxVotes = 0;
        uint8 winnerId = 0;
        bool tie = false;

        for (uint8 i = 1; i <= maxCandidateId; ++i) {
            if (!candidates[i].exists) continue;
            uint256 vc = candidates[i].totalVotes;
            if (vc > maxVotes) {
                maxVotes = vc;
                winnerId = i;
                tie = false;
            } else if (vc == maxVotes && vc != 0) {
                tie = true;
            }
        }

        require(winnerId != 0, "No winner found");

        partyNumber = candidates[winnerId].candidatePartyNumber;
        partyName = candidates[winnerId].candidatePartyName;
        candidatePolicy = candidates[winnerId].candidatePolicy;
        votes = candidates[winnerId].totalVotes;
        isTie = tie;
    }

    // ดึงรายชื่อแอดมินทั้งหมด
    function getAdmins() external view onlyAdmin returns (address[] memory) {
        return adminAddresses;
    }

    // ดึงข้อมูลสรุปการเลือกตั้ง
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

    // ดึงรหัสนักศึกษาจากบัญชีผู้เลือกตั้ง
    function getStudentIdByAccount(address account) external view onlyAdmin returns (string memory) {
        Voter storage voterData = voters[account];
        require(voterData.isRegistered, "Account not registered as voter");
        return voterData.studentId;
    }

    // ฟังก์ชันภายในตรวจสอบแอดมิน
    function isAdmin(address user) internal view returns (bool) {
        for(uint i = 0; i < adminAddresses.length; i++) {
            if(adminAddresses[i] == user) {
                return true;
            }
        }
        return false;
    }
}

//อ้างอิง
//โค้ดระบบโหวตเพิ่มผู้สมัครเลือกตั้ง
//https://github.com/andresudi/Voting-Smart-Contract
//https://gist.github.com/maheshmurthy/3da385a42678c3e36a8328cbe47cae5b
//https://github.com/ChaoticQubit/Solidity-Examples-in-Remix-IDE/blob/master/Ballot%20V1.sol

//บทความ + โค้ด
//https://medium.com/coinmonks/building-a-simple-voting-application-with-solidity-a99ff43cfa14
//https://medium.com/%40jannden/create-a-presidential-election-smart-contract-in-solidity-ec8145330c17
//https://dev.to/joshthecodingaddict/building-a-decentralized-voting-system-with-smart-contracts-2k8?utm_source
