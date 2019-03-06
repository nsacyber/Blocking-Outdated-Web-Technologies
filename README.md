# Blocking-Outdated-Web-Technologies

Guidance for blocking outdated web technologies #nsacyber


## Background
Outdated software is a security problem for many large enterprises. Outdated browsers are particularly risky because they routinely execute untrusted code (such as JavaScript) from unknown parties (such as web advertisers). As browsers become outdated, the skill level for attackers to exploit them lowers. When a browser vulnerability is reported, security researchers and cyber actors begin research and exploitation of it, findings are shared, proof of concept exploits are published, and eventually the exploit is absorbed into easy to use exploit kits (such as Metasploit). A vulnerability can be exploited at any point along this timeline or even before it is reported. However, the skill level to exploit the vulnerability decreases until even script kiddies can compromise the flaw. NSA recommends maintaining browsers at the current release version to counter this threat. Details on how to implement automatic browser updates, even in low bandwidth environments, are on nsa.gov ([Security Configuration Guide for Browser Updates] (https://apps.nsa.gov/iaarchive/library/ia-guidance/security-configuration/applications/security-configuration-guide-for-browser-updates.cfm)). 

NSA recognizes that in some environments the shift to implementing automated browser updating can not be immediate. In some cases, organizations may rely on internally hosted applications that require an outdated browser. For these environments, NSA recommends deploying network boundary signatures to prevent outdated browsers from accessing the Internet. Blocking outdated browsers from accessing the Internet drastically reduces the risks from the browser's easily exploitable vulnerabilities. While best practice is to migrate away from the application requiring outdated software, outdated browser blocking can provide significant defense in the mean time. 


## Implementation
These signatures can be deployed at a layer 7 network appliance capable of string matching. While the signatures are designed to be system agnostic, differences in the regular expression engines used within the network appliance could necessitate minor changes to the script. The signatures will be annotated when regex issues are encountered. As with any network based signature, these rules should be implemented first in logging mode to determine impact on traffic flow. Investigation may be necessary if logging shows matching against a significant portion of network traffic. Once logging confirms acceptable impact, signature rules can be switched to block outdated browsers. If the network appliance supports it, a custom message should be displayed to users indicating that their request was blocked because their browser is outdated. 

Browser rules are based on the "User Agent String" that browsers report with each request. There are limitations to the User Agent String. Because the string can be modified by end users, it is not an assured way to prevent individuals determined to use outdated browsers. It does make doing so more complicated which is likely to pressure users into updating rather than just circumventing the rules. Additionally, browsers report version numbers differently amongst vendors. For some vendors, the version is reported granularly enough to block outdated browsers with precision. Other vendors only report the major version number, so the blocking must be more selective to ensure that legitimately updated browsers are not blocked. In all cases, the rules were crafted with a "do no harm" mindset where ambiguous User Agent Strings are assumed to be up to date. 

## Requirements
* Layer 7 (Application Layer) network appliance capable of string matching


## Testing
For ease of testing, use the PowerShell script. The script probes various websites masquerading as an outdated browser. The script will report an error on two conditions:
* When an outdated browser was allowed to communicate with the Internet
* When a non-outdated browser was prevented from communicating with the Internet 


## Quick Links:
* [Rules](https://github.com/nsacyber/OutdatedBrowserRules/rules.txt)
* [Testing Script](https://github.com/nsacyber/OutdatedBrowserRules/testBrowserBlocking.ps1)
* [Security Configuration Guide for Browser Updates](https://apps.nsa.gov/iaarchive/library/ia-guidance/security-configuration/applications/security-configuration-guide-for-browser-updates.cfm)
