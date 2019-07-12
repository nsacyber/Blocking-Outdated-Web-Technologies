# This script attempts to simulate accessing webpages using many different web browsers by 
# specifying different User-Agent strings in the HTTP headers to see which ones the WCF is 
# blocking for DoD to reduce the risk of Internet exploitation of known vulnerabilities in 
# older web browsers.  This script saves a .out.txt file with its output log in the current
# directory.


#This is a substring of the response from the network appliance when an outdated browser is blocked
$BlockedString= "*blocked website*" 

#Filename where output will be written
$outfile = ".\BrowserBlockingResults-" + (Get-Date -Format "yyyyMMdd-hhmm") + ".out.txt"

#Time to wait between requests. This is used in an over-abundance of caution to ensure that the script does not create a significant traffic bottleneck for target websites
$delay = 0.5 #seconds between each test

#Helper function to handle putting data both to the file and to the screen
function out ([string] $str, $display = $true) {
  Out-File -FilePath $outfile -Append -InputObject $str
  if($display){ echo $str }
}

#Helper function to sum an array. Used for reporting statistics
function Get-Sum ($a, $b=@{}) {
    return (($a.Values | Measure-Object -Sum).Sum + ($b.Values | Measure-Object -Sum).Sum)
}

# testUserAgents Function will test each of the user agent strings from the array below. Function call is at the end of this script
function testUserAgents  {
    out "This script will test $($agents.Count) browser versions. `nYou will see a summary when the script completes."
    out "To prevent creating a network bottleneck for the target website, a short delay is introduced between tests. Because of this, the script is expected to take approximately $([int]($agents.Count * $delay * 2 / 60)) minutes to complete."
    out "Testing in progress (You can lock your screen, but don't close this window!)...`n "
	
	#First we set up some variables to record statistics about the attempts we make
    $blocked_websites = @{}
    $accessed_websites = @{}
    $BrowserTypes = @("Chrom", "Edge", "Firefox", "Internet Explorer", "Opera", "Safari", "Other")
    $BrowserPermittedProperly = @{}
    $BrowserPermittedImproperly = @{}
    $BrowserRestrictedProperly = @{}
    $BrowserRestrictedImproperly = @{}
    $BrowserBehaviorUnknown = @{}
    foreach($browser in $BrowserTypes) {  
      $BrowserPermittedProperly[$browser] = 0
      $BrowserPermittedImproperly[$browser] = 0
      $BrowserRestrictedProperly[$browser] = 0
      $BrowserRestrictedImproperly[$browser] = 0
      $BrowserBehaviorUnknown[$browser] = 0
    }
	
	#Next we indicate a random place in the list of test URLs to begin testing
    $site = Get-Random -Minimum 0 -Maximum ($testURLs.Count - 1)  # start randomly in list and try different site every time
	
	#Finally we loop over all of the user-agents that we want to test and try websites until we either are allowed through or blocked (usually this occurs on the first website tried)
    for ($agent=0; $agent -lt ($agents.Count); $agent++) {
        $data = $agents[$agent]
        $Response = $null
        $response_received = $false #we will try URLs until we find one that works (otherwise give up)
        for($i=0; $i -lt ($testURLs.Count) -AND $response_received -eq $false; $i++) {
            $testURL = $testURLs[(($site++) % $testURLs.Count)]
            $Response = $null
            try {
                $Response = Invoke-WebRequest "$($TestURL)?time=$([int][double]::Parse((Get-Date -UFormat %s)))"  -Method 'GET' -UserAgent $data[2] -TimeoutSec 10
            } catch {
				#There are a few cases which would cause an error. We may eventually handle these differently, but for now, we'll just log the error and keep trying
				if($_.ErrorDetails.Message -like "*BLOCKED*") { out ("   " + $_.Exception.Status + ": " + $_.Exception.Message) }
				elseif($_.Exception.Status -like "*Timeout*") { out ("   " + $_.Exception.Status + ": " + $_.Exception.Message) }
				else {out ("   " + $_.Exception.Status + ": " + $_.Exception.Message) }
            }
            if($Response.content.length -gt 0) { $response_received = $true }
            Start-Sleep -s $delay #slow down
        }

		#if keep_trying is true, then we've gone through the entire list of URLs and were unable to communicate with any of them. Check Internet connectivity if this occurs
        if($response_received -eq $false) {
            out "$($agent+1)/$($agents.Count) Error: Internet connectivity problem. Script could not test $($data[1])"
            $BrowserBehaviorUnknown[$browser]++
            continue
        }
		
		#categorize the browser being tested and log the test results
        $browser = "Other"
        foreach($browserType in $BrowserTypes) { 
            if($data[1] -imatch $BrowserType) { $browser = $browserType }
        }
        If ($data[0] -eq "permitted" -AND $Response.content -like $BlockedString) {
            out "$($agent+1)/$($agents.Count) Error: The following browser version was expected to be permitted, but it was blocked:  $($data[1])"
            $BrowserRestrictedImproperly[$browser]++
			$blocked_websites[$testURL] = $true
        }
        ElseIf ($data[0] -eq "restricted" -AND -not($Response.content -like $BlockedString)) {
            out "$($agent+1)/$($agents.Count) Error: The following browser version was expected to be blocked, but it was permitted:  $($data[1])"
            $BrowserPermittedImproperly[$browser]++
			$accessed_websites[$testURL] = $true
        } 
        Else { 
            out "$($agent+1)/$($agents.Count) Successfully tried browser $($data[1]) accessing URL $testURL and it was $($data[0]) as expected." $false
            if($Response.content -like $BlockedString) { $BrowserRestrictedProperly[$browser]++; $blocked_websites[$testURL] = $true }
            else { $BrowserPermittedProperly[$browser]++; $accessed_websites[$testURL] = $true }
        }  
		
    }
	
	#All user-agents have been tested
    out "`nScript completed"
	
    # Output summary stats
    out " $(Get-Sum $BrowserPermittedProperly $BrowserRestrictedProperly) browser versions were handled correctly."
	out " $(($agents.Count) - (Get-Sum $BrowserPermittedProperly $BrowserRestrictedProperly) - (Get-Sum $BrowserBehaviorUnknown)) browser versions were not handled correctly. These versions are listed above." #Use subtraction here because network errors could cause strings to not be listed as properly or improperly handled
    out " $(Get-Sum $BrowserBehaviorUnknown) browser tests had inconclusive results due to network issues."

    out " $(Get-Sum $BrowserRestrictedImproperly $BrowserRestrictedProperly ) browser tests were blocked in total."
    out " $(Get-Sum $BrowserPermittedImproperly $BrowserPermittedProperly ) browser tests were permitted in total."
    foreach($BrowserType in $BrowserTypes) {
      $browser = $BrowserType
      if($BrowserType -eq "Chrom") { $browser = "Chrome" }
      out "  For $($browser): $($BrowserPermittedProperly[$BrowserType]) allowed properly, $($BrowserRestrictedProperly[$BrowserType]) blocked properly, $($BrowserPermittedImproperly[$BrowserType]) incorrectly allowed, $($BrowserRestrictedImproperly[$BrowserType]) incorrectly blocked, $($BrowserBehaviorUnknown[$BrowserType]) network error encountered." 
    }
	
    # Look for possible websites that have a complete exception to the outdated browsers rules or overriding block
    foreach ($url in $testURLs) {
      if($blocked_websites.ContainsKey($url) -and $accessed_websites.ContainsKey($url)) {}
      elseif($blocked_websites.ContainsKey($url) -and -not ($accessed_websites.ContainsKey($url))) {
        echo ("Possible URL issue: " + $url + " was blocked in all attempts.")
      } elseif(-not ($blocked_websites.ContainsKey($url)) -and ($accessed_websites.ContainsKey($url))) {
        echo ("Possible URL issue: " + $url + " was accessed in all attempts.")
      } else {
          echo ("Possible URL issue: " + $url + " had problems being accessed in all attempts, but was not explicitly blocked by a browser block.")
      }
    }
    out "`n"
}

#This list of user agents was obtained from https://developers.whatismybrowser.com 
#It represents the most common ~350 user agent strings that are encountered online. Additional work was performed to identify which of these user agents should be blocked
$agents = @( 
("permitted","Android Browser 4","Mozilla/5.0 (Linux; U; Android 2.3.6; en-us; Huawei-U8665 Build/HuaweiU8665B037) AppleWebKit/533.1 (KHTML, like Gecko) Version/4.0 Mobile Safari/533.1","Android","Average"),
("permitted","Android Browser 4.1","Mozilla/5.0 (Linux; U; Android 4.1.2; en-us; ALCATEL ONE TOUCH 5020N Build/JZO54K) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.1 Mobile Safari/534.30","Android","Average"),
("permitted","Android Browser 4.2","Mozilla/5.0 (Linux; U; Android 4.2.2; en-us; ALCATEL ONETOUCH P310A Build/JDQ39) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.2 Mobile Safari/534.30","Android","Average"),
("permitted","BlackBerry Browser 7.1","Mozilla/5.0 (BlackBerry; U; BlackBerry 9320; en) AppleWebKit/534.11+ (KHTML, like Gecko) Version/7.1.0.714 Mobile Safari/534.11+","BlackBerry OS","Average"),
("restricted","Chrome 10","Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/534.16 (KHTML, like Gecko) Chrome/10.0.648.133 Safari/534.16","Windows","Average"),
("restricted","Chrome 11","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/534.24 (KHTML, like Gecko) Chrome/11.0.696.71 Safari/534.24","Windows","Average"),
("restricted","Chrome 12","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.53 Safari/534.30","Windows","Average"),
("restricted","Chrome 13","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/535.1 (KHTML, like Gecko) Chrome/13.0.782.24 Safari/535.1","Windows","Average"),
("restricted","Chrome 14","Mozilla/5.0 (Windows NT 5.1) AppleWebKit/535.1 (KHTML, like Gecko) Chrome/14.0.835.202 Safari/535.1","Windows","Average"),
("restricted","Chrome 15","Mozilla/5.0 (Windows NT 6.0) AppleWebKit/535.2 (KHTML, like Gecko) Chrome/15.0.874.120 Safari/535.2","Windows","Average"),
("restricted","Chrome 16","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/535.7 (KHTML, like Gecko) Chrome/16.0.912.77 Safari/535.7","Windows","Average"),
("restricted","Chrome 17","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/535.11 (KHTML, like Gecko) Chrome/17.0.963.56 Safari/535.11","Windows","Average"),
("restricted","Chrome 18","Mozilla/5.0 (Linux; Android 4.1.1; Nexus 7 Build/JRO03D) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.166 Safari/535.19","Android","Average"),
("restricted","Chrome 19","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/536.5 (KHTML, like Gecko) Chrome/19.0.1084.56 Safari/536.5","Mac OS X","Average"),
("restricted","Chrome 20","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_4) AppleWebKit/536.11 (KHTML, like Gecko) Chrome/20.0.1132.47 Safari/536.11","Mac OS X","Average"),
("restricted","Chrome 21","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_5_8) AppleWebKit/537.1 (KHTML, like Gecko) Chrome/21.0.1180.90 Safari/537.1","Mac OS X","Average"),
("restricted","Chrome 22","Mozilla/5.0 (X11; Linux armv6l) AppleWebKit/537.4 (KHTML, like Gecko) Chrome/22.0.1229.94 Safari/537.4","Linux","Average"),
("restricted","Chrome 23","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11","Windows","Average"),
("restricted","Chrome 24","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/537.17 (KHTML, like Gecko) Chrome/24.0.1312.52 Safari/537.17","Mac OS X","Average"),
("restricted","Chrome 25","Mozilla/5.0 (Windows NT 6.0) AppleWebKit/537.22 (KHTML, like Gecko) Chrome/25.0.1364.152 Safari/537.22","Windows","Average"),
("restricted","Chrome 26","Mozilla/5.0 (Linux; Android 4.0.4; BNTV600 Build/IMM76L) AppleWebKit/537.31 (KHTML, like Gecko) Chrome/26.0.1410.58 Safari/537.31","Android","Average"),
("restricted","Chrome 27","Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.116 Safari/537.36 HubSpot Webcrawler","Windows","Average"),
("restricted","Chrome 28","Mozilla/5.0 (Linux; Android 4.4.2; en-us; SAMSUNG-SM-G900A Build/KOT49H) AppleWebKit/537.36 (KHTML, like Gecko) Version/1.6 Chrome/28.0.1500.94 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 29","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/29.0.1547.2 Safari/537.36","Windows","Average"),
("restricted","Chrome 3","Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/532.0 (KHTML, like Gecko) Chrome/3.0.195.27 Safari/532.0","Windows","Average"),
("restricted","Chrome 30","Mozilla/5.0 (Linux; Android 4.4.2; 7040N Build/KVT49L) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/30.0.0.0 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 31","Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/31.0.1650.59 Safari/537.36","Windows","Average"),
("restricted","Chrome 32","Mozilla/5.0 (X11; CrOS x86_64 4920.71.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/32.0.1700.95 Safari/537.36","ChromeOS","Average"),
("restricted","Chrome 33","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/33.0.1750.5 Safari/537.36","Windows","Average"),
("restricted","Chrome 34","Mozilla/5.0 (Linux; Android 5.0.2; LG-V410/V41020c Build/LRX22G) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/34.0.1847.118 Safari/537.36 evaliant","Android","Average"),
("restricted","Chrome 35","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) MxNitro/1.0.1.3000 Chrome/35.0.1849.0 Safari/537.36","Windows","Average"),
("restricted","Chrome 36","Mozilla/5.0 (Linux; Android 4.4.4; Nexus 7 Build/KTU84P) AppleWebKit/537.36 (KHTML like Gecko) Chrome/36.0.1985.135 Safari/537.36","Android","Average"),
("restricted","Chrome 37","Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) WhiteHat Aviator/37.0.2062.99 Chrome/37.0.2062.99 Safari/537.36","Windows","Average"),
("restricted","Chrome 38","Mozilla/5.0 (Linux; Android 5.1.1; LGMS345 Build/LMY47V) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/38.0.2125.102 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 39","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36","Windows","Average"),
("restricted","Chrome 4","Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/531.3 (KHTML, like Gecko) Chrome/4.0.249.89 Safari/531.3","Windows","Average"),
("restricted","Chrome 40","Mozilla/5.0 (Linux; Android 5.1.1; Nexus 4 Build/LMY48T) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/40.0.2214.89 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 41","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36","Windows","Average"),
("restricted","Chrome 42","Mozilla/5.0 (Linux; Android 4.0.4; BNTV400 Build/IMM76L) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.111 Safari/537.36","Android","Average"),
("restricted","Chrome 43","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/43.0.2357.130 Safari/537.36","Windows","Average"),
("restricted","Chrome 44","Mozilla/5.0 (Linux; Android 6.0; Android SDK built for x86 Build/MASTER; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/44.0.2403.119 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 45","Mozilla/5.0 (Windows NT 6.3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.85 Safari/537.36","Windows","Average"),
("restricted","Chrome 46","Mozilla/5.0 (Linux; Android 5.1.1; Coolpad 3622A Build/LMY47V; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/46.0.2490.76 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 47","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.80 Safari/537.36","Windows","Average"),
("restricted","Chrome 48","Mozilla/5.0 (Linux; Android 5.1.1; 5065N Build/LMY47V) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.95 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 49","Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.108 Safari/537.36","Windows","Average"),
("restricted","Chrome 5","Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US) AppleWebKit/533.4 (KHTML, like Gecko) Chrome/5.0.375.99 Safari/533.4","Windows","Average"),
("restricted","Chrome 50","Mozilla/5.0 (Linux; Android 5.1.1; LGMS330 Build/LMY47V) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.89 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 51","Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.79 Safari/537.36","Windows","Average"),
("restricted","Chrome 52","Mozilla/5.0 (Linux; Android 6.0.1; SM-J210F Build/MMB29Q) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.98 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 53","Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.89 Safari/537.36","Windows","Average"),
("restricted","Chrome 54","Mozilla/5.0 (Linux; Android 6.0.1; Redmi 4 Build/MMB29M) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/54.0.2840.85 Mobile Safari/537.36","Android","Average"),
("restricted","Chrome 55","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883 Safari/537.36","Windows","Average"),
("restricted","Chrome 56","AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.87 Safari/537.36","--","Average"),
("permitted","Chrome 57","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2970.0 Safari/537.36","Windows","Average"),
("permitted","Chrome 58","Mozilla/5.0 (Linux; Android 7.0; LGMS210 Build/NRD90U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.83 Mobile Safari/537.36","Android","Average"),
("permitted","Chrome 59","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.86 Safari/537.36 PTST/384","Windows","Average"),
("restricted","Chrome 6","Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/534.3 (KHTML, like Gecko) Chrome/6.0.472.62 Safari/534.3","Windows","Average"),
("permitted","Chrome 60","Mozilla/5.0 (Linux; Android 7.0; HUAWEI NXT-AL10 Build/HUAWEINXT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.107 Mobile Safari/537.36","Android","Average"),
("permitted","Chrome 61","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.79 Safari/537.36","Windows","Average"),
("permitted","Chrome 62","Mozilla/5.0 (Linux; Android 7.0; LGMS210 Build/NRD90U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/62.0.3202.84 Mobile Safari/537.36","Android","Average"),
("permitted","Chrome 63","Mozilla/5.0 (Windows NT 6.3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.84 Safari/537.36","Windows","Average"),
("permitted","Chrome 64","Mozilla/5.0 (Linux; Android 7.0; LGMS210 Build/NRD90U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.137 Mobile Safari/537.36","Android","Average"),
("permitted","Chrome 65","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3298.3 Safari/537.36","Mac OS X","Average"),
("permitted","Chrome 66","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/66.0.3359.6 Safari/537.36","Windows","Average"),
("permitted","Chrome 67","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/67.0.2526.73 Safari/537.36","Windows","Average"),
("permitted","Chrome 68","Mozilla/5.0 (Windows; U; Windows NT 10.0; en-US) AppleWebKit/604.1.38 (KHTML, like Gecko) Chrome/68.0.3325.162","Windows","Average"),
("permitted","Chrome 69","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3445.2 Safari/537.36","Windows","Average"),
("permitted","Chrome 70","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.77 Safari/537.36","Windows","Average"),
("permitted","Chrome 71","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3202.75 Safari/537.36","Windows","Average"),
("permitted","Chrome 72","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Safari/537.36","Mac OS X","Average"),
("permitted","Chrome 73","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3163.100 Safari/537.36","Windows","Average"),
("restricted","Chromium 20","Mozilla/5.0 (X11; Linux i686) AppleWebKit/536.11 (KHTML, like Gecko) Ubuntu/12.04 Chromium/20.0.1132.47 Chrome/20.0.1132.47 Safari/536.11","Linux","Average"),
("restricted","Chromium 27","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/535.11 (KHTML, like Gecko) Ubuntu/11.10 Chromium/27.0.1453.93 Chrome/27.0.1453.93 Safari/537.36","Linux","Average"),
("restricted","Chromium 34","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/34.0.1847.116 Chrome/34.0.1847.116 Safari/537.36","Linux","Average"),
("permitted","Chromium 35","Mozilla/5.0 (Linux; Ubuntu 14.04 like Android 4.4) AppleWebKit/537.36 Chromium/35.0.1870.2 Mobile Safari/537.36","Android","Average"),
("restricted","Chromium 37","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/37.0.2062.120 Chrome/37.0.2062.120 Safari/537.36","Linux","Average"),
("restricted","Chromium 44","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/44.0.2403.89 Chrome/44.0.2403.89 Safari/537.36","Linux","Average"),
("restricted","Chromium 45","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/45.0.2454.101 Chrome/45.0.2454.101 Safari/537.36","Linux","Average"),
("restricted","Chromium 47","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/47.0.2526.73 Chrome/47.0.2526.73 Safari/537.36","Linux","Average"),
("restricted","Chromium 48","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/48.0.2564.82 Chrome/48.0.2564.82 Safari/537.36","Linux","Average"),
("restricted","Chromium 49","Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/49.0.2623.108 Chrome/49.0.2623.108 Safari/537.36","Linux","Average"),
("restricted","Chromium 50","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/50.0.2661.102 Chrome/50.0.2661.102 Safari/537.36","Linux","Average"),
("restricted","Chromium 51","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/51.0.2704.79 Chrome/51.0.2704.79 Safari/537.36","Linux","Average"),
("restricted","Chromium 52","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/52.0.2743.116 Chrome/52.0.2743.116 Safari/537.36","Linux","Average"),
("restricted","Chromium 53","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/53.0.2785.143 Chrome/53.0.2785.143 Safari/537.36","Linux","Average"),
("restricted","Chromium 55","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/55.0.2883.87 Chrome/55.0.2883.87 Safari/537.36","Linux","Average"),
("restricted","Chromium 56","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/56.0.2924.76 Chrome/56.0.2924.76 Safari/537.36","Linux","Average"),
("permitted","Chromium 57","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/57.0.2987.98 Chrome/57.0.2987.98 Safari/537.36","Linux","Average"),
("permitted","Chromium 58","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/58.0.3029.110 Chrome/58.0.3029.110 Safari/537.36","Linux","Average"),
("permitted","Chromium 59","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/59.0.3071.109 Chrome/59.0.3071.109 Safari/537.36","Linux","Average"),
("permitted","Chromium 60","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/60.0.3112.113 Chrome/60.0.3112.113 Safari/537.36","Linux","Average"),
("permitted","Chromium 61","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/61.0.3163.79 Chrome/61.0.3163.79 Safari/537.36","Linux","Average"),
("permitted","Chromium 62","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/62.0.3202.94 Chrome/62.0.3202.94 Safari/537.36","Linux","Average"),
("permitted","Chromium 63","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/63.0.3239.84 Chrome/63.0.3239.84 Safari/537.36","Linux","Average"),
("permitted","Chromium 64","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/64.0.3282.167 Chrome/64.0.3282.167 Safari/537.36","Linux","Average"),
("permitted","Chromium 65","Mozilla/5.0 (Win) AppleWebKit/1000.0 (KHTML, like Gecko) Chrome/65.663 Safari/1000.01","Windows","Average"),
("permitted","Chromium 66","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/66.0.3359.6 Safari/537.36","Windows","Average"),
("permitted","Chromium 67","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/67.0.2526.73 Safari/537.36","Windows","Average"),
("permitted","Chromium 68","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/68.0.3239.84 Chrome/68.0.3239.84 Safari/537.36","Linux","Average"),
("permitted","Chromium 69","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/69.0.3239.84 Chrome/69.0.3239.84 Safari/537.36","Linux","Average"),
("permitted","Chromium 70","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chromium/70.0.3163.100  Chrome/70.0.3163.100 Safari/537.36","Linux","Average"),
("permitted","Chromium 71","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/71.0.3239.84 Chrome/71.0.3239.84 Safari/537.36","Linux","Average"),
("permitted","Chromium 72","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/72.0.3239.84 Chrome/72.0.3239.84 Safari/537.36","Linux","Average"),
("permitted","Chromium 73","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/73.0.3239.84 Chrome/73.0.3239.84 Safari/537.36","Linux","Average"),
("permitted","Edge 16","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.135 Safari/537.36 Edge/12.10136","Windows","Average"),
("permitted","Edge 20","Mozilla/5.0 (Windows NT 10.0; Win64; x64; WebView/3.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.135 Safari/537.36 Edge/12.10240","Windows","Average"),
("permitted","Edge 25","Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox One) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2486.0 Safari/537.36 Edge/13.10586","Windows","Average"),
("permitted","Edge 34","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2486.0 Safari/537.36 Edge/14.14300","Windows","Average"),
("permitted","Edge 38","Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox One) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.79 Safari/537.36 Edge/14.14393","Windows","Average"),
("permitted","Edge 40","Mozilla/5.0 (Windows Phone 10.0; Android 6.0.1; Xbox; Xbox One) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.116 Mobile Safari/537.36 Edge/15.15063","Windows Phone","Average"),
("permitted","Edge 41","Mozilla/5.0 (Windows NT 10.0; Win64; x64; WebView/3.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36 Edge/16.16299","Windows","Average"),
("permitted","Edge 42","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.140 Safari/537.36 Edge/17.17134","Windows","Average"),
("permitted","Edge 44","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.102 Safari/537.36 Edge/18.18305","Windows","Average"),
("restricted","Firefox 10","Mozilla/5.0 (Windows NT 6.1; rv:6.0) Gecko/20110814 Firefox/10.0.1","Windows","Average"),
("restricted","Firefox 11","Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:11.0) Gecko/20100101 Firefox/11.0","Linux","Average"),
("restricted","Firefox 12","Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; rv:11.0) like Gecko/20100101 Firefox/12.0","Windows","Average"),
("restricted","Firefox 13","Mozilla/5.0 (Macintosh; Intel Mac OS X 10.7; rv:13.0) Gecko/20100101 Firefox/13.0.1","Mac OS X","Average"),
("restricted","Firefox 14","Mozilla/5.0 (Windows NT 6.0; rv:14.0) Gecko/20100101 Firefox/14.0.1","Windows","Average"),
("restricted","Firefox 15","Mozilla/5.0 (Macintosh; Intel Mac OS X 10.5; rv:15.0) Gecko/20100101 Firefox/15.0.1","Mac OS X","Average"),
("restricted","Firefox 16","Mozilla/5.0 (Windows NT 6.2; WOW64; rv:16.0) Gecko/20100101 Firefox/16.0","Windows","Average"),
("restricted","Firefox 17","Mozilla/5.0 (X11; Linux i686; rv:17.0) Gecko/20100101 Firefox/17.0","Linux","Average"),
("restricted","Firefox 18","Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:18.0) Gecko/20130119 Firefox/18.0","Windows","Average"),
("restricted","Firefox 19","Mozilla/5.0 (Windows NT 6.0; WOW64; rv:19.0) Gecko/20100101 Firefox/19.0","Windows","Average"),
("restricted","Firefox 20","Mozilla/5.0 (Windows NT 6.2; rv:20.0) Gecko/20121202 Firefox/20.0","Windows","Average"),
("restricted","Firefox 21","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:21.0) Gecko/20130331 Firefox/21.0","Linux","Average"),
("restricted","Firefox 22","Mozilla/5.0 (Windows NT 5.1; rv:22.0) Gecko/20100101 Firefox/22.0","Windows","Average"),
("restricted","Firefox 23","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:23.0) Gecko/20100101 Firefox/23.0","Linux","Average"),
("restricted","Firefox 24","Mozilla/5.0 (Windows NT 5.1; rv:24.0) Gecko/20100101 Firefox/24.0","Windows","Average"),
("restricted","Firefox 25","Mozilla/5.0 (Macintosh; Intel Mac OS X 10.6; rv:25.0) Gecko/20100101 Firefox/25.0","Mac OS X","Average"),
("restricted","Firefox 26","Mozilla/5.0 (Windows NT 6.1; rv:26.0) Gecko/20100101 Firefox/26.0","Windows","Average"),
("restricted","Firefox 27","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:27.0) Gecko/20100101 Firefox/27.0","Windows","Average"),
("restricted","Firefox 28","Mozilla/5.0 (Mobile; ALCATELOneTouch4019A; rv:28.0) Gecko/28.0 Firefox/28.0","--","Average"),
("restricted","Firefox 29","Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:25.0) Gecko/20100101 Firefox/29.0","Windows","Average"),
("restricted","Firefox 3","Mozilla/5.0 (X11; U; Linux i686; fr; rv:1.9.0.9) Gecko/2009042113 Ubuntu/9.04 (jaunty) Firefox/3.0.9","Linux","Average"),
("restricted","Firefox 30","Mozilla/5.0 (Windows NT 6.3; WOW64; rv:30.0) Gecko/20100101 Firefox/30.0","Windows","Average"),
("restricted","Firefox 31","Mozilla/5.0 (X11; Linux i586; rv:31.0) Gecko/20100101 Firefox/31.0","Linux","Average"),
("restricted","Firefox 32","Mozilla/5.0 (Windows NT 5.1; rv:32.0) Gecko/20100101 Firefox/32.0","Windows","Average"),
("restricted","Firefox 33","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:33.0) Gecko/20100101 Firefox/33.0","Linux","Average"),
("restricted","Firefox 34","Mozilla/5.0 (Windows NT 6.3; WOW64; rv:34.0) Gecko/20100101 Firefox/34.0 AlexaToolbar/alxf-2.21","Windows","Average"),
("restricted","Firefox 35","Mozilla/5.0 (Android; Mobile; rv:35.0) Gecko/35.0 Firefox/35.0","Android","Average"),
("restricted","Firefox 36","Mozilla/5.0 (Windows NT 10.0; WOW64; rv:36.0) Gecko/20100101 Firefox/36.0","Windows","Average"),
("restricted","Firefox 37","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:37.0) Gecko/20100101 Firefox/37.0","Linux","Average"),
("restricted","Firefox 38","Mozilla/5.0 (Windows NT 6.1; rv:38.0) Gecko/20100101 Firefox/38.0 (IndeedBot 1.1)","Windows","Average"),
("restricted","Firefox 39","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:39.0) Gecko/20100101 Firefox/39.0","Linux","Average"),
("restricted","Firefox 4","Mozilla/5.0 (Windows NT 5.1; rv:2.0.1) Gecko/20100101 Firefox/4.0.1","Windows","Average"),
("restricted","Firefox 40","Mozilla/5.0 (Windows NT 6.2; WOW64; rv:40.0) Gecko/20100101 Firefox/40.0","Windows","Average"),
("restricted","Firefox 41","Mozilla/5.0 (Android 4.4; Mobile; rv:41.0) Gecko/41.0 Firefox/41.0","Android","Average"),
("restricted","Firefox 42","Mozilla/5.0 (Windows NT 6.3; Win64; x64; rv:42.0) Gecko/20100101 Firefox/42.0","Windows","Average"),
("restricted","Firefox 43","Mozilla/5.0 (Android 5.1.1; Mobile; rv:43.0) Gecko/43.0 Firefox/43.0","Android","Average"),
("restricted","Firefox 44","Mozilla/5.0 (Windows NT 6.3; rv:44.0) Gecko/20100101 Firefox/44.0","Windows","Average"),
("restricted","Firefox 45","Mozilla/5.0 (Android 5.0.2; Tablet; rv:45.0) Gecko/45.0 Firefox/45.0","Android","Average"),
("restricted","Firefox 46","Mozilla/5.0 (Windows NT 6.0; rv:46.0) Gecko/20100101 Firefox/46.0","Windows","Average"),
("restricted","Firefox 47","Mozilla/5.0 (Android 4.4.2; Mobile; rv:47.0) Gecko/47.0 Firefox/47.0","Android","Average"),
("restricted","Firefox 48","Mozilla/5.0 (Windows NT 6.2; rv:48.0) Gecko/20100101 Firefox/48.0","Windows","Average"),
("restricted","Firefox 49","Mozilla/5.0 (X11; NetBSD amd64; rv:49.0) Gecko/20100101 Firefox/49.0","A UNIX based OS","Average"),
("restricted","Firefox 5","Mozilla/5.0 (Windows NT 5.1; rv:5.0) Gecko/20100101 Firefox/5.0","Windows","Average"),
("restricted","Firefox 50","Mozilla/5.0 (Android 5.1.1; Mobile; rv:50.0) Gecko/50.0 Firefox/50.0","Android","Average"),
("restricted","Firefox 51","Mozilla/5.0 (Windows NT 6.0; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0","Windows","Average"),
("permitted","Firefox 52","Mozilla/5.0 (Android 6.0.1; Mobile; rv:52.0) Gecko/52.0 Firefox/52.0","Android","Average"),
("permitted","Firefox 53","Mozilla/5.0 (Windows NT 6.3; rv:53.0) Gecko/20100101 Firefox/53.0","Windows","Average"),
("permitted","Firefox 54","Mozilla/5.0 (Android 6.0.1; Mobile; rv:54.0) Gecko/54.0 Firefox/54.0","Android","Average"),
("permitted","Firefox 55","Mozilla/5.0 (Windows NT 6.2; WOW64; rv:55.0) Gecko/20100101 Firefox/55.0","Windows","Average"),
("permitted","Firefox 56","Mozilla/5.0 (Android 7.0; Mobile; rv:56.0) Gecko/56.0 Firefox/56.0","Android","Average"),
("permitted","Firefox 57","Mozilla/5.0 (Windows NT 6.3; rv:57.0) Gecko/20100101 Firefox/57.0","Windows","Average"),
("permitted","Firefox 58","Mozilla/5.0 (Android 7.0; Mobile; rv:58.0) Gecko/58.0 Firefox/58.0","Android","Average"),
("permitted","Firefox 59","Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:59.0) Gecko/20100101 Firefox/59.0","Windows","Average"),
("permitted","Firefox 60","Mozilla/5.0 (Android 7.5.9; Mobile; rv:60.0) Gecko/60.0 Firefox/60.0","Windows","Average"),
("permitted","Firefox 61","Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:61.0) Gecko/20100101 Firefox/61.0","Windows","Average"),
("permitted","Firefox 62","Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:62.0) Gecko/20100101 Firefox/62.0","Windows","Average"),
("permitted","Firefox 63","Mozilla/5.0 (Android 9; Tablet; rv:63.0) Gecko/63.0 Firefox/63.0","Windows","Average"),
("permitted","Firefox 64","Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:64.0) Gecko/20100101 Firefox/64.0","Windows","Average"),
("permitted","Firefox 65","Mozilla/6.0 (Windows NT 10.0; rv:36.0) Gecko/20100101 Firefox/65.0.1","Windows","Average"),
("restricted","Internet Explorer 10","Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Win64; x64; Trident/6.0)","Windows","Average"),
("restricted","Internet Explorer 10","Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; WOW64; Trident/6.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)","Windows","Average"),
("permitted","Internet Explorer 11","Mozilla/5.0 (Windows NT 6.3; WOW64; Trident/7.0; MAARJS; rv:11.0) like Gecko","Windows","Average"),
("permitted","Internet Explorer 11","Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; WOW64; Trident/7.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; .NET4.0C; .NET4.0E)","Windows","Average"),
("restricted","Internet Explorer 10","Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.2; Win64; x64; Trident/7.0)","Windows","Average"),
("permitted","Internet Explorer 6","Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; .NET CLR 2.0.50727; .NET CLR 1.1.4322)","Windows","Average"),
("permitted","Internet Explorer 7 (allowed for now for compatibility)","Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1)","Windows","Average"),
("restricted","Internet Explorer 8","Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; eSobiSubscriber 2.0.4.16; MAAR; .NET4.0C; McAfee; BRI/2; BOIE9;ENUS)","Windows","Average"),
("restricted","Internet Explorer 8","Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET CLR 1.1.4322; .NET4.0C; InfoPath.3; MS-RTC LM 8; .NET4.0E)","Windows","Average"),
("restricted","Internet Explorer 8","Mozilla/4.0 (compatible; MSIE 8.0; Win32)","Windows","Average"),
("restricted","Internet Explorer 9","Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.0; Trident/5.0; BOIE9;ENUSMSCOM)","Windows","Average"),
("restricted","Internet Explorer 9","Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; Trident/5.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)","Windows","Average"),
("restricted","Internet Explorer 9","Mozilla/5.0 (compatible; MSIE 10.6; Windows NT 6.1; Trident/5.0; InfoPath.2; SLCC1; .NET CLR 3.0.4506.2152; .NET CLR 3.5.30729; .NET CLR 2.0.50727) 3gpp-gba UNTRUSTED/1.0","Windows","Average"),
("restricted","Internet Explorer 9","Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1)","Windows","Average"),
("restricted","Internet Explorer 9","Mozilla/5.0 (compatible; MSIE 9.11; Windows NT 6.1; Trident/5.0)","Windows","Average"),
("restricted","Internet Explorer 9","Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/5.0)","Windows","Average"),
("restricted","Internet Explorer 9","Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; Trident/5.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; InfoPath.2; .NET4.0C)","Windows","Average"),
("restricted","Internet Explorer Mobile 10","Mozilla/5.0 (compatible; MSIE 10.0; Windows Phone 8.0; Trident/6.0; IEMobile/10.0; ARM; Touch; NOKIA; Lumia 820)","Windows Phone","Average"),
("permitted","Internet Explorer Mobile 11","Mozilla/5.0 (Mobile; Windows Phone 8.1; Android 4.0; ARM; Trident/7.0; Touch; rv:11.0; IEMobile/11.0; NOKIA; Lumia 630) like iPhone OS 7_0_3 Mac OS X AppleWebKit/537 (KHTML, like Gecko) Mobile Safari/537","Windows Phone","Average"),
("restricted","Internet Explorer Mobile 9","Mozilla/5.0 (compatible; MSIE 9.0; Windows Phone OS 7.5; Trident/5.0; IEMobile/9.0)","Windows Phone","Average"),
("restricted","Opera 10","Opera/9.80 (Windows NT 5.1; U; en) Presto/2.2.15 Version/10.10","Windows","Average"),
("restricted","Opera 11","Opera/9.80 (X11; Linux zvav; U; en) Presto/2.8.119 Version/11.10","Linux","Average"),
("restricted","Opera 11.2","Mozilla/5.0 (Linux; U; Android 5.0.2; zh-CN; Redmi Note 3 Build/LRX22G) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 OPR/11.2.3.102637 Mobile Safari/537.36","Android","Average"),
("restricted","Opera 12","Opera/9.80 (Android 2.3.7; Linux; Opera Mobi/46154) Presto/2.11.355 Version/12.10","Android","Average"),
("restricted","Opera 14","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.12 Safari/537.36 OPR/14.0.1116.4","Windows","Average"),
("restricted","Opera 15","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/28.0.1500.29 Safari/537.36 OPR/15.0.1147.24 (Edition Next)","Windows","Average"),
("restricted","Opera 20","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/33.0.1750.154 Safari/537.36 OPR/20.0.1387.91","Windows","Average"),
("restricted","Opera 22","Mozilla/5.0 (Linux armv7l) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/35.0.1916.153 Safari/537.36 OPR/22.0.1481.0 OMI/4.2.12.48.ALSAN3.56","Linux","Average"),
("restricted","Opera 26","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.95 Safari/537.36 OPR/26.0.1656.60","Windows","Average"),
("restricted","Opera 28","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2272.76 Safari/537.36 OPR/28.0.1750.40","Windows","Average"),
("restricted","Opera 30","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/43.0.2357.81 Safari/537.36 OPR/30.0.1835.49","Windows","Average"),
("restricted","Opera 31","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.155 Safari/537.36 OPR/31.0.1889.174","Mac OS X","Average"),
("restricted","Opera 32","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.85 Safari/537.36 OPR/32.0.1948.25","Windows","Average"),
("restricted","Opera 33","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.86 Safari/537.36 OPR/33.0.1990.115","Windows","Average"),
("restricted","Opera 34","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.73 Safari/537.36 OPR/34.0.2036.25","Windows","Average"),
("restricted","Opera 35","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.82 Safari/537.36 OPR/35.0.2066.37","Windows","Average"),
("restricted","Opera 36","Mozilla/5.0 (Windows NT 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.112 Safari/537.36 OPR/36.0.2130.80","Windows","Average"),
("restricted","Opera 37","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.94 Safari/537.36 OPR/37.0.2178.43","Windows","Average"),
("restricted","Opera 38","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.106 Safari/537.36 OPR/38.0.2220.41","Mac OS X","Average"),
("restricted","Opera 39","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.82 Safari/537.36 OPR/39.0.2256.48","Windows","Average"),
("restricted","Opera 40","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.101 Safari/537.36 OPR/40.0.2308.62","Windows","Average"),
("restricted","Opera 41","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/54.0.2840.99 Safari/537.36 OPR/41.0.2353.69","Windows","Average"),
("restricted","Opera 42","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.87 Safari/537.36 OPR/42.0.2393.137","Windows","Average"),
("restricted","Opera 43","Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.87 Safari/537.36 OPR/43.0.2442.1144","Windows","Average"),
("restricted","Opera 44","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.98 Safari/537.36 OPR/44.0.2510.857","Windows","Average"),
("permitted","Opera 45","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.81 Safari/537.36 OPR/45.0.2552.812","Windows","Average"),
("permitted","Opera 46","Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3053.3 Safari/537.36 OPR/46.0.2573.0 (Edition developer)","Linux","Average"),
("permitted","Opera 47","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.78 Safari/537.36 OPR/47.0.2631.55","Windows","Average"),
("permitted","Opera 48","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.100 Safari/537.36 OPR/48.0.2685.39","Mac OS X","Average"),
("permitted","Opera 49","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/62.0.3202.89 Safari/537.36 OPR/49.0.2725.47","Windows","Average"),
("permitted","Opera 49","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/62.0.3202.62 Safari/537.36 OPR/49.0.2725.34","Windows","Average"),
("permitted","Opera 50","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36 OPR/50.0.2762.67","Windows","Average"),
("permitted","Opera 51","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.140 Safari/537.36 OPR/51.0.2830.34","Windows","Average"),
("permitted","Opera 52","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Safari/537.36 OPR/52.0.2871.40","Windows","Average"),
("permitted","Opera 53","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/66.0.3343.3 Safari/537.36 OPR/53.0.2885.0","Windows","Average"),
("permitted","Opera 54","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/67.0.3386.1 Safari/537.36 OPR/54.0.2929.0","Windows","Average"),
("permitted","Opera 55","Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/68.0.3440.15 Safari/537.36 OPR/55.0.2991.0","Windows","Average"),
("permitted","Opera 56","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36 OPR/56.0.3051.116","Windows","Average"),
("permitted","Opera 57","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.102 Safari/537.36 OPR/57.0.3098.102","Windows","Average"),
("permitted","Opera 58","Mozilla/5.0 (Windows NT 6.2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36 OPR/58.0.3135.53","Windows","Average"),
("restricted","Opera Mini ","Opera/9.80 (J2ME/MIDP; Opera Mini; U; en) Presto/2.12.423 Version/12.16","--","Average"),
("restricted","Opera Mini 18","Opera/9.80 (Android; Opera Mini/18.0.2254/37.8923; U; en) Presto/2.12.423 Version/12.16","Android","Average"),
("restricted","Opera Mini 20","Opera/9.80 (Android; Opera Mini/20.0.2254/37.9178; U; en) Presto/2.12.423 Version/12.16","Android","Average"),
("restricted","Opera Mini 20.1","Opera/9.80 (Android; Opera Mini/20.1.2254/37.9178; U; en) Presto/2.12.423 Version/12.16","Android","Average"),
("restricted","Opera Mini 24","Opera/9.80 (Android; Opera Mini/24.0.2254/62.178; U; en) Presto/2.12.423 Version/12.16","Android","Average"),
("restricted","Opera Mini 27","Opera/9.80 (Android; Opera Mini/27.0.2254/66.247; U; en) Presto/2.12.423 Version/12.16","Android","Average"),
("restricted","Opera Mini 28","Opera/9.80 (Android; Opera Mini/28.0.2254/66.318; U; en) Presto/2.12.423 Version/12.16","Android","Average"),
("restricted","Opera Mini 31","Opera/9.80 (Android; Opera Mini/31.0.2254/77.161; U; en) Presto/2.12.423 Version/12.16","Android","Average"),
("restricted","Opera Mini 4.1","Opera/9.80 (J2ME/MIDP; Opera Mini/4.1.11355/28.3590; U; en) Presto/2.8.119 Version/11.10","--","Average"),
("restricted","Opera Mini 4.2","Opera/9.80 (J2ME/MIDP; Opera Mini/4.2/28.3590; U; en) Presto/2.8.119 Version/11.10","--","Average"),
("restricted","Opera Mini 4.4","Opera/9.80 (SpreadTrum; Opera Mini/4.4.31492/59.323; U; en) Presto/2.12.423 Version/12.16","--","Average"),
("restricted","Opera Mini 9","Opera/9.80 (J2ME/MIDP; Opera Mini/9.80 (S60; SymbOS; Opera Mobi/23.348; U; en) Presto/2.5.25 Version/10.54","Symbian","Average"),
("permitted","Safari 10.1","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13) AppleWebKit/603.1.13 (KHTML, like Gecko) Version/10.1 Safari/603.1.13","Mac OS X","Average"),
("permitted","Safari 11.1","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.1 Safari/605.1.15","Mac OS X","Average"),
("restricted","Safari 4","Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17","Mac OS X","Average"),
("restricted","Safari 4","Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_3; en-us) AppleWebKit/531.21.11 (KHTML, like Gecko) Version/4.0.4 Safari/531.21.10","Mac OS X","Average"),
("restricted","Safari 4","Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_2; en-us) AppleWebKit/531.21.8 (KHTML, like Gecko) Version/4.0.4 Safari/531.21.10","Mac OS X","Average"),
("restricted","Safari 4","Mozilla/5.0 (Windows; U; Windows NT 6.0; en-US) AppleWebKit/528.16 (KHTML, like Gecko) Version/4.0 Safari/528.16","Windows","Average"),
("restricted","Safari 4.1","Mozilla/5.0 (Macintosh; U; PPC Mac OS X 10_4_11; en) AppleWebKit/533.19.4 (KHTML, like Gecko) Version/4.1.3 Safari/533.19.4","Mac OS X","Average"),
("restricted","Safari 4.1","Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_4_11; fr) AppleWebKit/533.19.4 (KHTML, like Gecko) Version/4.1.3 Safari/533.19.4","Mac OS X","Average"),
("restricted","Safari 5","Mozilla/5.0 (Macintosh; PPC Mac OS X 10_5_8) AppleWebKit/534.50.2 (KHTML, like Gecko) Version/5.0.6 Safari/533.22.3","Mac OS X","Average"),
("permitted","Mobile Safari 5.1","Mozilla/5.0 (iPhone; CPU iPhone OS 5_1 like Mac OS X) AppleWebKit/534.46 (KHTML, like Gecko) Version/5.1 Mobile/9B176 Safari/7534.48.3","iOS","Average"),
("restricted","Safari 5.1","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_8) AppleWebKit/534.58.2 (KHTML, like Gecko) Version/5.1.8 Safari/534.58.2","Mac OS X","Average"),
("permitted","Mobile Safari 6","Mozilla/5.0 (iPad; CPU OS 6_1_2 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/6.0 Mobile/10B146 Safari/8536.25","iOS","Average"),
("restricted","Safari 6","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_3) AppleWebKit/536.29.13 (KHTML, like Gecko) Version/6.0.4 Safari/536.29.13","Mac OS X","Average"),
("restricted","Safari 6.2","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_5) AppleWebKit/600.3.18 (KHTML, like Gecko) Version/6.2.3 Safari/537.85.12","Mac OS X","Average"),
("permitted","Mobile Safari 7","Mozilla/5.0 (iPad; CPU OS 7_1 like Mac OS X) AppleWebKit/537.51.2 (KHTML, like Gecko) Version/7.0 Mobile/11D167 Safari/9537.53","iOS","Average"),
("restricted","Safari 7","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_3) AppleWebKit/537.75.14 (KHTML, like Gecko) Version/7.0.3 Safari/7046A194A evaliant","Mac OS X","Average"),
("restricted","Safari 7.1","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/600.2.5 (KHTML, like Gecko) Version/7.1.2 Safari/537.85.11","Mac OS X","Average"),
("permitted","Mobile Safari 8","Mozilla/5.0 (iPhone; CPU iPhone OS 8_1_3 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12B466 Safari/600.1.4","iOS","Average"),
("restricted","Safari 8","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10) AppleWebKit/537.36 (KHTML, like Gecko) Version/8.0 Safari/537.36","Mac OS X","Average"),
("restricted","Safari 8.1","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11) AppleWebKit/601.1.32 (KHTML, like Gecko) Version/8.1 Safari/601.1.32","Mac OS X","Average"),
("permitted","Mobile Safari 9","Mozilla/5.0 (iPad; CPU OS 9_0 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13A344 Safari/601.1","iOS","Average"),
("restricted","Safari 9","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11) AppleWebKit/601.1.39 (KHTML, like Gecko) Version/9.0 Safari/601.1.39","Mac OS X","Average"),
("restricted","Safari 10","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_3) AppleWebKit/602.4.8 (KHTML, like Gecko) Version/10.0.3 Safari/602.4.8","Mac OS X","Average"),
("permitted","Safari 11","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_6) AppleWebKit/604.1.28 (KHTML, like Gecko) Version/11.0 Safari/604.1.28","Mac OS X","Average"),
("permitted","Safari 12","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0 Safari/605.1.15","Mac OS X","Average"),
("restricted","Chrome 11","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/534.24 (KHTML, like Gecko) Chrome/11.0.696.34 Safari/534.24","Linux","Common"),
("restricted","Chrome 13","Mozilla/5.0 (Windows NT 6.0) AppleWebKit/535.1 (KHTML, like Gecko) Chrome/13.0.782.112 Safari/535.1","Windows","Common"),
("restricted","Chrome 16","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/535.7 (KHTML, like Gecko) Chrome/16.0.912.77 Safari/535.7","Windows","Common"),
("restricted","Chrome 17","Mozilla/5.0 (Windows NT 5.1) AppleWebKit/535.11 (KHTML, like Gecko) Chrome/17.0.963.56 Safari/535.11","Windows","Common"),
("restricted","Chrome 19","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/536.5 (KHTML, like Gecko) Chrome/19.0.1084.56 Safari/536.5","Windows","Common"),
("restricted","Chrome 20","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/536.11 (KHTML, like Gecko) Chrome/20.0.1132.57 Safari/536.11","Windows","Common"),
("restricted","Chrome 22","Mozilla/5.0 (Linux; U) AppleWebKit/537.4 (KHTML, like Gecko) Chrome/22.0.1229.79 Safari/537.4","Linux","Common"),
("restricted","Chrome 24","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.17 (KHTML, like Gecko) Chrome/24.0.1312.52 Safari/537.17","Windows","Common"),
("restricted","Chrome 26","Mozilla/5.0 (Windows NT 6.0) AppleWebKit/537.31 (KHTML, like Gecko) Chrome/26.0.1410.64 Safari/537.31","Windows","Common"),
("restricted","Chrome 27","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.94 Safari/537.36","Windows","Common"),
("restricted","Chrome 28","Mozilla/5.0 (Linux; Android 4.4.2; en-us; SAMSUNG SCH-I545 Build/KOT49H) AppleWebKit/537.36 (KHTML, like Gecko) Version/1.5 Chrome/28.0.1500.94 Mobile Safari/537.36","Android","Common"),
("restricted","Chrome 30","Mozilla/5.0 (Linux; Android 4.4; Nexus 5 Build/LMY48B ) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/30.0.0.0 Mobile Safari/537.36","Android","Common"),
("restricted","Chrome 34","Mozilla/5.0 (Linux; Android 4.4.2; Nexus 4 Build/KOT49H) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/34.0.1847.114 Mobile Safari/537.36","Android","Common"),
("restricted","Chrome 36","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1985.143 Safari/537.36","Windows","Common"),
("restricted","Chrome 37","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.124 Safari/537.36","Mac OS X","Common"),
("restricted","Chrome 40","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/40.0.2214.115 Safari/537.36","Windows","Common"),
("restricted","Chrome 41","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.1 Safari/537.36","Mac OS X","Common"),
("restricted","Chrome 42","Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.90 Safari/537.36","Windows","Common"),
("restricted","Chrome 43","Mozilla/5.0 (Linux; Android 5.1.1; Nexus 5 Build/LMY48B; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/43.0.2357.65 Mobile Safari/537.36","Android","Common"),
("restricted","Chrome 44","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.157 Safari/537.36","Windows","Common"),
("restricted","Chrome 45","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.101 Safari/537.36","Mac OS X","Common"),
("restricted","Chrome 46","Mozilla/5.0 (Windows NT 5.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.86 Safari/537.36","Windows","Common"),
("restricted","Chrome 47","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/47.0.2526.106 Safari/537.36","Mac OS X","Common"),
("restricted","Chrome 48","Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.97 Safari/537.36","Windows","Common"),
("restricted","Chrome 49","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.87 Safari/537.36","Linux","Common"),
("restricted","Chrome 50","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.75 Safari/537.36","Windows","Common"),
("restricted","Chrome 51","Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.106 Safari/537.36","Linux","Common"),
("permitted","Chrome 52","Mozilla/5.0 (X11; CrOS x86_64 8350.68.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.116 Safari/537.36","ChromeOS","Common"),
("permitted","Chrome 53","Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.116 Safari/537.36","Windows","Common"),
("permitted","Chrome 54","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/54.0.2840.71 Safari/537.36","Mac OS X","Common"),
("permitted","Chrome 55","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.87 Safari/537.36","Windows","Common"),
("permitted","Chrome 56","Mozilla/5.0 (X11; CrOS x86_64 9000.91.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/56.0.2924.110 Safari/537.36","ChromeOS","Common"),
("permitted","Chrome 57","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.98 Safari/537.36","Windows","Common"),
("permitted","Chrome 58","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36","Mac OS X","Common"),
("permitted","Chrome 59","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.115 Safari/537.36","Windows","Common"),
("permitted","Chrome 60","Mozilla/5.0 (Linux; Android 6.0.1; SM-T800 Build/MMB29K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.107 Safari/537.36","Android","Common"),
("permitted","Chrome 61","Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36","Windows","Common"),
("permitted","Chrome 62","Mozilla/5.0 (X11; CrOS x86_64 9901.77.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/62.0.3202.97 Safari/537.36","ChromeOS","Common"),
("permitted","Chrome 63","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36","Windows","Common"),
("permitted","Chrome 64","Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.167 Safari/537.36","Windows","Common"),
("permitted","Edge ","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.116 Safari/537.36 Edge/15.9200","Windows","Common"),
("permitted","Edge ","Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36 Edge/12.0","Windows","Common"),
("permitted","Edge ","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.79 Safari/537.36 Edge/14.9200","Windows","Common"),
("permitted","Edge ","Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36 Edge/12.0","Windows","Common"),
("permitted","Edge ","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2486.0 Safari/537.36 Edge/13.9200","Windows","Common"),
("permitted","Edge 20","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.135 Safari/537.36 Edge/12.10240","Windows","Common"),
("permitted","Edge 25","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2486.0 Safari/537.36 Edge/13.10586","Windows","Common"),
("permitted","Edge 38","Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.79 Safari/537.36 Edge/14.14393","Windows","Common"),
("permitted","Edge 40","Mozilla/5.0 (Windows NT 10.0; Win64; x64; Xbox; Xbox One) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/52.0.2743.116 Safari/537.36 Edge/15.15063","Windows","Common"),
("permitted","Edge 41","Mozilla/5.0 (Windows Phone 10.0; Android 6.0.1; Xbox; Xbox One) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Mobile Safari/537.36 Edge/16.16299","Windows Phone","Common"),
("restricted","Firefox 10","Mozilla/5.0 (X11; Linux i686; rv:10.0.2) Gecko/20100101 Firefox/10.0.2 DejaClick/2.4.1.6","Linux","Common"),
("restricted","Firefox 12","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:12.0) Gecko/20100101 Firefox/12.0","Windows","Common"),
("restricted","Firefox 13","Mozilla/5.0 (Windows NT 5.1; rv:13.0) Gecko/20100101 Firefox/13.0.1","Windows","Common"),
("restricted","Firefox 14","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:14.0) Gecko/20100101 Firefox/14.0.1","Windows","Common"),
("restricted","Firefox 15","Mozilla/5.0 (Windows NT 6.1; rv:15.0) Gecko/20120716 Firefox/15.0a2","Windows","Common"),
("restricted","Firefox 16","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:16.0) Gecko/20100101 Firefox/16.0","Windows","Common"),
("restricted","Firefox 17","Mozilla/5.0 (Windows NT 6.1; rv:17.0) Gecko/20100101 Firefox/17.0","Windows","Common"),
("restricted","Firefox 18","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:18.0) Gecko/20100101 Firefox/18.0","Windows","Common"),
("restricted","Firefox 19","Mozilla/5.0 (Windows NT 6.1; rv:19.0) Gecko/20100101 Firefox/19.0","Windows","Common"),
("restricted","Firefox 20","Mozilla/5.0 (X11; Linux x86_64; rv:10.0) Gecko/20150101 Firefox/20.0 (Chrome)","Linux","Common"),
("restricted","Firefox 24","Mozilla/5.0 (Windows NT 6.1; rv:24.0) Gecko/20100101 Firefox/24.0","Windows","Common"),
("restricted","Firefox 26","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:26.0) Gecko/20100101 Firefox/26.0","Windows","Common"),
("restricted","Firefox 28","Mozilla/5.0 (Windows NT 6.3; WOW64; rv:28.0) Gecko/20100101 Firefox/28.0","Windows","Common"),
("restricted","Firefox 29","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:29.0) Gecko/20120101 Firefox/29.0","Windows","Common"),
("restricted","Firefox 3","Mozilla/5.0 (Windows; U; Windows NT 5.1; en-US; rv:1.9.0.1) Gecko/2008070208 Firefox/3.0.1","Windows","Common"),
("restricted","Firefox 30","Ruby, Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:30.0) Gecko/20100101 Firefox/30.0","Mac OS X","Common"),
("restricted","Firefox 31","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:31.0) Gecko/20100101 Firefox/31.0","Windows","Common"),
("restricted","Firefox 32","Mozilla/5.0 (Windows NT 6.1; rv:32.0) Gecko/20100101 Firefox/32.0","Windows","Common"),
("restricted","Firefox 33","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10; rv:33.0) Gecko/20100101 Firefox/33.0","Mac OS X","Common"),
("restricted","Firefox 34","Mozilla/5.0 (Windows NT 6.1; rv:34.0) Gecko/20100101 Firefox/34.0","Windows","Common"),
("restricted","Firefox 35","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:35.0) Gecko/20100101 Firefox/35.0","Windows","Common"),
("restricted","Firefox 36","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:36.0) Gecko/20100101 Firefox/36.0","Windows","Common"),
("restricted","Firefox 37","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:37.0) Gecko/20100101 Firefox/37.0","Windows","Common"),
("restricted","Firefox 38","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:38.0) Gecko/20100101 Firefox/38.0","Windows","Common"),
("restricted","Firefox 39","Mozilla/5.0 (Windows NT 5.1; WOW64; rv:39.0) Gecko/20100101 Firefox/39.0","Windows","Common"),
("restricted","Firefox 4","Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.4) Gecko/20100101 Firefox/4.0","Linux","Common"),
("restricted","Firefox 40","Mozilla/5.0 (Windows NT 5.1; rv:40.0) Gecko/20100101 Firefox/40.0","Windows","Common"),
("restricted","Firefox 41","Mozilla/5.0 (Macintosh; Intel Mac OS X 10.10; rv:41.0) Gecko/20100101 Firefox/41.0","Mac OS X","Common"),
("restricted","Firefox 42","Mozilla/5.0 (Windows NT 5.1; rv:42.0) Gecko/20100101 Firefox/42.0","Windows","Common"),
("restricted","Firefox 43","Mozilla/5.0 (Macintosh; Intel Mac OS X 10.10; rv:43.0) Gecko/20100101 Firefox/43.0","Mac OS X","Common"),
("restricted","Firefox 44","Mozilla/5.0 (Windows NT 6.1; rv:44.0) Gecko/20100101 Firefox/44.0","Windows","Common"),
("permitted","Firefox 45","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:45.0) Gecko/20100101 Firefox/45.0","Linux","Common"),
("permitted","Firefox 46","Mozilla/5.0 (Windows NT 5.1; rv:46.0) Gecko/20100101 Firefox/46.0","Windows","Common"),
("permitted","Firefox 47","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:47.0) Gecko/20100101 Firefox/47.0","Linux","Common"),
("permitted","Firefox 48","Mozilla/5.0 (Windows NT 5.1; rv:48.0) Gecko/20100101 Firefox/48.0","Windows","Common"),
("permitted","Firefox 49","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:49.0) Gecko/20100101 Firefox/49.0","Linux","Common"),
("restricted","Firefox 5","Mozilla/5.0 (Windows NT 6.1; WOW64; rv:5.0) Gecko/20100101 Firefox/5.0","Windows","Common"),
("permitted","Firefox 50","Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:50.0) Gecko/20100101 Firefox/50.0","Windows","Common"),
("permitted","Firefox 51","Mozilla/5.0 (X11; Linux x86_64; rv:51.0) Gecko/20100101 Firefox/51.0","Linux","Common"),
("permitted","Firefox 52","Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:52.0) Gecko/20100101 Firefox/52.0","Windows","Common"),
("permitted","Firefox 53","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:53.0) Gecko/20100101 Firefox/53.0","Linux","Common"),
("permitted","Firefox 54","Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:54.0) Gecko/20100101 Firefox/54.0","Windows","Common"),
("permitted","Firefox 55","Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:55.0) Gecko/20100101 Firefox/55.0","Linux","Common"),
("permitted","Firefox 56","Mozilla/5.0 (Windows NT 6.3; Win64; x64; rv:56.0) Gecko/20100101 Firefox/56.0","Windows","Common"),
("permitted","Firefox 57","Mozilla/5.0 (X11; Linux x86_64; rv:57.0) Gecko/20100101 Firefox/57.0","Linux","Common"),
("permitted","Firefox 58","Mozilla/5.0 (Windows NT 6.1; rv:58.0) Gecko/20100101 Firefox/58.0","Windows","Common"),
("restricted","Firefox 6","Mozilla/5.0 (Windows NT 5.1; rv:6.0.2) Gecko/20100101 Firefox/6.0.2","Windows","Common"),
("permitted","Mobile Safari 10","Mozilla/5.0 (iPad; CPU OS 10_3_1 like Mac OS X) AppleWebKit/603.1.30 (KHTML, like Gecko) Version/10.0 Mobile/14E304 Safari/602.1","iOS","Common"),
("permitted","Safari 10.1","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/603.2.5 (KHTML, like Gecko) Version/10.1.1 Safari/603.2.5","Mac OS X","Common"),
("permitted","Mobile Safari 11","Mozilla/5.0 (iPad; CPU OS 11_2_5 like Mac OS X) AppleWebKit/604.5.6 (KHTML, like Gecko) Version/11.0 Mobile/15D60 Safari/604.1","iOS","Common"),
("permitted","Safari 11","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/604.5.6 (KHTML, like Gecko) Version/11.0.3 Safari/604.5.6","Mac OS X","Common"),
("permitted","Mobile Safari 4","Mozilla/5.0 (iPhone; U; CPU iPhone OS 3_0 like Mac OS X; en-us) AppleWebKit/528.18 (KHTML, like Gecko) Version/4.0 Mobile/7A341 Safari/528.16","iOS","Common"),
("restricted","Safari 4.1","Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_4_11; en) AppleWebKit/533.19.4 (KHTML, like Gecko) Version/4.1.3 Safari/533.19.4","Mac OS X","Common"),
("permitted","Mobile Safari 5","Mozilla/5.0 (iPad; U; CPU OS 4_3_5 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8L1 Safari/6533.18.5","iOS","Common"),
("restricted","Safari 5","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_5_8) AppleWebKit/534.50.2 (KHTML, like Gecko) Version/5.0.6 Safari/533.22.3","Mac OS X","Common"),
("permitted","Mobile Safari 5.1","Mozilla/5.0 (iPad; CPU OS 5_1_1 like Mac OS X) AppleWebKit/534.46 (KHTML, like Gecko) Version/5.1 Mobile/9B206 Safari/7534.48.3","iOS","Common"),
("restricted","Safari 5.1","Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/534.57.2 (KHTML, like Gecko) Version/5.1.7 Safari/534.57.2","Windows","Common"),
("permitted","Mobile Safari 6","Mozilla/5.0 (iPad; CPU OS 6_1_3 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/6.0 Mobile/10B329 Safari/8536.25","iOS","Common"),
("permitted","Mobile Safari 7","Mozilla/5.0 (iPhone; CPU iPhone OS 7_0_4 like Mac OS X) AppleWebKit/537.51.1 (KHTML, like Gecko) Version/7.0 Mobile/11B554a Safari/9537.53","iOS","Common"),
("restricted","Safari 7","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_3) AppleWebKit/537.75.14 (KHTML, like Gecko) Version/7.0.3 Safari/7046A194A","Mac OS X","Common"),
("permitted","Mobile Safari 8","Mozilla/5.0 (iPhone; CPU iPhone OS 8_0 like Mac OS X) AppleWebKit/600.1.3 (KHTML, like Gecko) Version/8.0 Mobile/12A4345d Safari/600.1.4","iOS","Common"),
("restricted","Safari 8","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_4) AppleWebKit/600.7.12 (KHTML, like Gecko) Version/8.0.7 Safari/600.7.12","Mac OS X","Common"),
("permitted","Mobile Safari 9","Mozilla/5.0 (iPhone; CPU iPhone OS 9_0_1 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13A404 Safari/601.1","iOS","Common"),
("permitted","Safari 9","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/601.2.7 (KHTML, like Gecko) Version/9.0.1 Safari/601.2.7","Mac OS X","Common"),
("permitted","Safari 9.1","Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/601.7.8 (KHTML, like Gecko) Version/9.1.2 Safari/601.7.7","Mac OS X","Common")
)

#This should be a list of HTTP sites external to the tested network that is accustomed to significant traffic
#Because the list is iterated across for subsequent requests and there is a delay, the initial configuration will create a request to each of these sites every 2 seconds. 
$testURLs = @( "http://www.maryland.gov/Pages/default.aspx",
               "http://www.wsdot.wa.gov/",
               "http://www.hawaiicounty.gov/",
               "http://www.myflorida.com/",
			   "http://www.lacounty.gov/",
			   "http://www.idaho.gov/",
			   "http://www.kdheks.gov/",
			   "http://www.wyo.gov/",
			   "http://outdoornebraska.gov/",
			   "http://waynecountypa.gov/",
			   "http://cityofgunnison-co.gov/",
			   "http://redmond.gov/"			   
);


function DoExit  {
    Read-Host -Prompt "Press Enter to exit"
    exit
}
testUserAgents

DoExit