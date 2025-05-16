// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract VoteChainDGT_StudentIdValidator {
    // ฟังก์ชันตรวจสอบรหัสนักศึกษา
    function isValidStudentId(string memory studentId) public pure returns (bool) {
        if (bytes(studentId).length != 8) {
            return false;
        }
        bytes1 level = bytes(studentId)[0];
        if (level != "B" && level != "M" && level != "D") {
            return false;
        }
        uint256 checksum = (uint256(uint8(bytes(studentId)[1])) - 48) *
            49 +
            (uint256(uint8(bytes(studentId)[2])) - 48) *
            7 +
            (uint256(uint8(bytes(studentId)[3])) - 48) *
            49 +
            (uint256(uint8(bytes(studentId)[4])) - 48) *
            7 +
            (uint256(uint8(bytes(studentId)[5])) - 48) *
            49 +
            (uint256(uint8(bytes(studentId)[6])) - 48) *
            7;
        checksum = checksum % 10;
        uint256 lastDigit = uint256(uint8(bytes(studentId)[7])) - 48;
        return checksum == lastDigit;
    }
}
