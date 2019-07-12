# Blocking-Outdated-Web-Technologies

Guidance for blocking outdated web technologies #nsacyber


## Background
Outdated software is a security problem for many large enterprises. Outdated browsers are particularly risky because they routinely execute untrusted code (such as JavaScript) from unknown parties (such as web advertisers). As browsers become outdated, the skill level for attackers to exploit them lowers. When a browser vulnerability is reported, security researchers and cyber actors begin research and exploitation, findings are shared, proof of concept exploits are published, and eventually the exploit is absorbed into easy-to-use exploit kits. A vulnerability can be exploited at any point along this timeline or even before it is reported. However, the skill level to exploit the vulnerability decreases over time until unskilled script kiddies can compromise the browser flaw. NSA recommends maintaining browsers as close as possible to the current release version to counter this threat. Details on how to implement automatic browser updates, even in low bandwidth environments, are on nsa.gov [Security Configuration Guide for Browser Updates](https://apps.nsa.gov/iaarchive/library/ia-guidance/security-configuration/applications/security-configuration-guide-for-browser-updates.cfm). 

NSA recognizes that in some environments the shift to implementing automated browser updating cannot be immediate. In some cases, organizations may rely on internally hosted applications that require an outdated browser. For these environments, NSA recommends deploying network boundary signatures to prevent outdated browsers from accessing the Internet. Blocking outdated browsers from accessing the Internet drastically reduces the risk by blocking most threat actors from accessing the vulnerabilities. While best practice is to migrate away from the application requiring outdated software, outdated browser blocking can provide significant defense during the migration for little effort. 


## Implementing the Rules
These signatures can be deployed at a layer 7 network appliance capable of string matching. While the signatures are designed to be system agnostic, differences in the regular expression engines used within network appliance could necessitate minor changes to the script. The signatures will be annotated when regex issues are encountered. As with any network based signature, these rules should be implemented first in logging mode to determine impact on traffic flow. Investigation may be necessary if logging shows matching against a significant portion of network traffic. Once logging confirms acceptable impact, signature rules can be enabled to block outdated browsers. If the network appliance supports it, a custom message should be displayed to users indicating that their request was blocked because their browser is outdated. 

Browser rules are based on the "User Agent String" that browsers report with each request. There are limitations to the User Agent String. Because the string can be modified by end users, it is not an assured way to prevent individuals determined to use outdated browsers. Additionally, browsers report version numbers differently amongst vendors. For some vendors, the version is reported granularly enough to block outdated browsers with precision. Other vendors only report the major version number, so the blocking must be more selective to ensure that legitimately updated browsers are not blocked. In all cases, the rules were crafted with a "do no harm" mindset where ambiguous User Agent Strings are assumed to be up to date.

## Requirements
* Layer 7 (Application Layer) network appliance capable of string matching on regular expressions


## Testing the Rules
For ease of testing, use the PowerShell script. The script probes various websites masquerading as an outdated browser. The script will report an error on two conditions:
* When an outdated browser was allowed to communicate with the Internet
* When a non-outdated browser was prevented from communicating with the Internet

The testing script was designed on a Windows 10 endpoint, but should work on any updated Windows environment. To run the script, simply download to a local directory, right-click the script, and select "Run with PowerShell". When the script completes, you will see "Script completed" as well as a summary of the blocking results. A detailed summary will be saved in the same directory where the script was run using; output will have the filename "BrowserBlockingResultsYYYYMMDD-HHMM.out.txt" where YYYYMMDD and HHMM are the date and time that the script was run. Poor bandwidth can affect the accuracy of the testing script as websites may appear to be inaccessible due to dropped connections. For this reason, it is best to run the testing script during a time with low network traffic. 

Testing should be performed after signatures are enabled in "blocking" mode. The testing script will help network administrators to detect problems that could arise from other network appliance rules overriding the outdated browser rules. The testing scripts only test the effectiveness of the browser blocking script; network administrators should still perform their own verification that mission critical traffic is not affected by the browser blocking rules. 

Note that the testing script corresponds to a browser blocking rule set. Ensure that the testing script and the browser blocking ruleset are for the same year and quarter. The current blocking strategy is to block browsers that are more than 2 years outdated. Organizations can update the rules and testing script to block browsers less outdated to enhance their defensive posture. 

##Change Log
2019-07-12: Updated signatures to ignore false positive with O365 Identity Client Runtime Library (IDCRL) which advertises MSIE 6.0 


## Quick Links:
* [Rules](https://github.com/nsacyber/Blocking-Outdated-Web-Technologies/blob/master/RULES_browser_blocking_2019Q2.txt)
* [Testing Script](https://github.com/nsacyber/Blocking-Outdated-Web-Technologies/blob/master/TESTING_SCRIPT_browser_blocking_2019Q2.ps1)
* [Security Configuration Guide for Browser Updates](https://apps.nsa.gov/iaarchive/library/ia-guidance/security-configuration/applications/security-configuration-guide-for-browser-updates.cfm)
