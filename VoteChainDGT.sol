// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract VoteChainDGT {
    string public name = "VoteChainDGT";
    string public symbol = "DGT";
    uint8 public decimals = 0;
    uint256 public totalSupply;

    address public admin;
    uint256 public startTime;
    uint256 public endTime;

    // การเก็บข้อมูลผู้สมัคร
    struct Candidate {
        uint id;
        string title;
        string firstName;
        string lastName;
        string nickname;
        string partyName;
        string policy;
        uint partyNumber;
        uint voteCount;
        uint age;
    }

    // การเก็บข้อมูลผู้โหวต
    struct Voter {
        string title;
        string firstName;
        string lastName;
        string studentId;
        uint256 isRegistered; // 1 = ลงทะเบียนแล้ว, 0 = ยังไม่ได้ลงทะเบียน
        uint256 hasVoted; // 1 = โหวตแล้ว, 0 = ยังไม่ได้โหวต
        uint256 usedTokens;  // จำนวนโทเคนที่ใช้ไป
    }

    mapping(address => Voter) public voters;
    Candidate[] public candidates;
    address[] public voterAddresses; // Array สำหรับเก็บที่อยู่ของผู้โหวตที่ลงทะเบียน

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier onlyDuringVoting() {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Voting is not active");
        _;
    }

    modifier onlyOnce() {
        require(voters[msg.sender].hasVoted == 0, "You have already voted");
        _;
    }

    modifier onlyRegistered() {
        require(voters[msg.sender].isRegistered == 1, "You are not registered to vote");
        _;
    }

    modifier canRegister() {
        // ผู้ใช้งานต้องสามารถลงทะเบียนได้ใหม่เมื่อการเลือกตั้งเริ่มใหม่
        require(block.timestamp >= startTime, "Voting period has not started yet");
        require(block.timestamp <= endTime, "Voting period has ended");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    // ฟังก์ชันตรวจสอบรหัสนักศึกษา
    function isValidID(string memory studentID) internal pure returns (bool) {
        if (bytes(studentID).length != 8) {
            return false;
        }

        // ตรวจสอบตัวอักษรแรก
        bytes1 level = bytes(studentID)[0];  // เปลี่ยนเป็น bytes1
        if (level != 'B' && level != 'M' && level != 'D') {
            return false;
        }

        // คำนวณ checksum
        uint checksum = (uint(uint8(bytes(studentID)[1])) - 48) * 49 +
                        (uint(uint8(bytes(studentID)[2])) - 48) * 7 +
                        (uint(uint8(bytes(studentID)[3])) - 48) * 49 +
                        (uint(uint8(bytes(studentID)[4])) - 48) * 7 +
                        (uint(uint8(bytes(studentID)[5])) - 48) * 49 +
                        (uint(uint8(bytes(studentID)[6])) - 48) * 7;
        checksum = checksum % 10;

        // ตรวจสอบตัวเลขสุดท้าย
        uint lastDigit = uint(uint8(bytes(studentID)[7])) - 48;
        return checksum == lastDigit;
    }

    // ------------------------
    // 📌 Admin functions
    // ------------------------

    // ตั้งเวลาเลือกตั้ง
    function setVotingPeriod(uint256 _startTime, uint256 _endTime) public onlyAdmin {
        require(_endTime > _startTime, "End time must be after start time");
        startTime = _startTime;
        endTime = _endTime;
    }

    // เพิ่มผู้สมัคร
    function addCandidate(
        uint _id,
        string memory _title, // คำนำหน้าชื่อ
        string memory _firstName,
        string memory _lastName,
        string memory _nickname, // ย้ายไว้หลัง _lastName
        string memory _partyName,
        string memory _policy,
        uint _partyNumber, // หมายเลขพรรค
        uint _age // อายุของผู้สมัคร
    ) public onlyAdmin {
        // ตรวจสอบว่า _id และ _partyNumber ต้องเป็นเลขเดียวกัน
        require(_id == _partyNumber, "ID and Party Number must be the same");

        candidates.push(Candidate(_id, _title, _firstName, _lastName, _nickname, _partyName, _policy, _partyNumber, 0, _age));
    }

    // ดึงข้อมูลผู้สมัครตาม _id
    function getCandidateById(uint _id) public view returns (
        uint id,
        string memory title, // คำนำหน้าชื่อ
        string memory firstName,
        string memory nickname,
        string memory lastName,
        string memory partyName,
        string memory policy,
        uint partyNumber,
        uint voteCount,
        uint age // อายุของผู้สมัคร
    ) {
        for (uint i = 0; i < candidates.length; i++) {
            if (candidates[i].id == _id) {
                Candidate memory candidate = candidates[i];
                return (
                    candidate.id,
                    candidate.title, // คำนำหน้าชื่อ
                    candidate.firstName,
                    candidate.nickname,
                    candidate.lastName,
                    candidate.partyName,
                    candidate.policy,
                    candidate.partyNumber,
                    candidate.voteCount,
                    candidate.age // อายุของผู้สมัคร
                );
            }
        }
        revert("Candidate not found");
    }

    // แก้ไขข้อมูลผู้สมัคร
    function updateCandidate(
        uint _id,
        string memory _title, // คำนำหน้าชื่อ
        string memory _firstName,
        string memory _lastName,
        string memory _nickname, // ย้ายไว้หลัง _lastName
        string memory _partyName,
        string memory _policy,
        uint _partyNumber, // หมายเลขพรรค
        uint _age // อายุของผู้สมัคร
    ) public onlyAdmin {
        // ค้นหาผู้สมัครที่ตรงกับ _id
        for (uint i = 0; i < candidates.length; i++) {
            if (candidates[i].id == _id) {
                // อัปเดตข้อมูลผู้สมัคร
                candidates[i].title = _title;
                candidates[i].firstName = _firstName;
                candidates[i].lastName = _lastName;
                candidates[i].nickname = _nickname;
                candidates[i].partyName = _partyName;
                candidates[i].policy = _policy;
                candidates[i].partyNumber = _partyNumber;
                candidates[i].age = _age;
                return;
            }
        }
        revert("Candidate not found");
    }

    // ------------------------
    // 📌 Voter functions
    // ------------------------

    // ลงทะเบียนผู้โหวต
    function registerVoter(
        string memory _title, // คำนำหน้า
        string memory _firstName,
        string memory _lastName,
        string memory _studentId
    ) public canRegister {
        require(voters[msg.sender].isRegistered == 0, "You are already registered");

        // ตรวจสอบรหัสนักศึกษาว่าถูกต้องหรือไม่
        require(isValidID(_studentId), "Invalid student ID");

        // ลงทะเบียนผู้โหวต
        voters[msg.sender] = Voter(_title, _firstName, _lastName, _studentId, 1, 0, 0);  // 1 = ลงทะเบียนแล้ว
        voterAddresses.push(msg.sender); // เก็บที่อยู่ผู้โหวต
    }

    // ดูผู้ลงทะเบียนทั้งหมดและแสดงโทเคนที่มีและที่ใช้
    function getRegisteredVotersWithTokens() public view returns (Voter[] memory) {
        Voter[] memory registeredVoters = new Voter[](voterAddresses.length);
        for (uint i = 0; i < voterAddresses.length; i++) {
            address voterAddr = voterAddresses[i];
            Voter storage voter = voters[voterAddr];
            registeredVoters[i] = Voter(
                voter.title,
                voter.firstName,
                voter.lastName,
                voter.studentId,
                voter.isRegistered,  // 1 = ลงทะเบียนแล้ว
                voter.hasVoted,      // 1 = โหวตแล้ว
                voter.usedTokens     // จำนวนโทเคนที่ใช้
            );
        }
        return registeredVoters;
    }

    // โหวต
    function vote(uint _partyNumber, string memory _studentId) public onlyDuringVoting onlyRegistered onlyOnce {
        // ตรวจสอบว่า _studentId ตรงกับรหัสนักศึกษาของผู้โหวต
        require(keccak256(bytes(voters[msg.sender].studentId)) == keccak256(bytes(_studentId)), "Student ID does not match");

        // ค้นหาผู้สมัครที่ตรงกับ _partyNumber
        bool found = false;
        for (uint i = 0; i < candidates.length; i++) {
            if (candidates[i].partyNumber == _partyNumber) {
                // เพิ่มคะแนนให้กับผู้สมัครที่ตรงกับ _partyNumber
                candidates[i].voteCount += 1;
                voters[msg.sender].hasVoted = 1;
                voters[msg.sender].usedTokens += 1;  // เพิ่มจำนวนโทเคนที่ใช้
                found = true;
                break;
            }
        }

        // หากไม่พบผู้สมัครที่มี _partyNumber ตรงกับที่กรอก
        require(found, "Invalid party number");
    }

    // ------------------------
    // 📌 Token functions
    // ------------------------

    // Mint (สร้างโทเคนใหม่)
    function mint(address to, uint256 amount) public onlyAdmin {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    // Burn (ลบโทเคนหลังการใช้สิทธิ์โหวต)
    function burn(uint256 amount) public onlyRegistered {
        require(voters[msg.sender].hasVoted == 1, "You need to vote before burning your token");
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        voters[msg.sender].hasVoted = 0;  // รีเซ็ตสถานะโหวต
    }

    // เก็บยอดโทเคนของแต่ละ address
    mapping(address => uint256) public balanceOf;
}
