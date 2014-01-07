#!/usr/bin/tclsh8.5

;# human-looking webcrawler, in tcl

set version {0.1}

package require http

;# NOTE: we're using 1 to mean true and 0 to mean false
;# not sure if this is how TCL does it, but it's our convention

;# TODO: support crawling ssl pages

;# a regular expression to detect all urls in the text
set url_regex {https?://(?:[a-zA-Z0-9\-]+\.)+[a-zA-Z0-9\-]+(?:/[a-zA-Z0-9\-?&=:./]+)*}

;# another url regex for what we can actually recurse to, as our http lib doesn't have ssl support
set crawl_url_regex {http://(?:[a-zA-Z0-9\-]+\.)+[a-zA-Z0-9\-]+(?:/[a-zA-Z0-9\-?&=:./]+)*}

;# TODO crawl urls that reference other pages on the same site also

;# a list of hosts /not/ to crawl
set host_blacklist [list {w3.org} {charter.net}]

;# BEGIN GENERAL HELPER FUNCTIONS

;# get a substring from the given string
proc st_substr {str start length} {
	set newstr ""
	for {set n $start} {[expr {$n-$start}]<$length} {incr n} {
		set newstr "$newstr[string index $str $n]"
	}
	return $newstr
}

;# search for a substring within a string and return the index of the first match
;# will return -1 if no match is found, otherwise it will return the index of the start of the first match
proc st_search {str substr} {
	set found -1
	;# for each string character
	for {set n 0} {$n<[string length $str]} {incr n} {
		;# until we find a character that doesn't match assume this substring is here
		set was_found 1
		
		;# check for the characters of the substring
		for {set n2 0} {$n2<[string length $substr]} {incr n2} {
			
			;# if a character is out of place
			if {[string index $str [expr {$n+$n2}]]!=[string index $substr $n2]} {
				;#didn't find a match yet
				set was_found 0
				;#break the loop so we don't waste cpu cycles
				set n2 [string length $substr]
			}
		}
		
		;# we found the substring, we're done
		if {$was_found} {
			return $n
		}
	}
	return $found
}

;# END GENERAL HELPER FUNCTIONS

;# a recursive function to crawl a web page
;# returns TRUE on success, FALSE on failure
proc crawl_page {url index_regex} {
	global url_regex
	global crawl_url_regex
	global host_blacklist
	
	puts "crawl_page debug 0, trying to crawl page $url"
	
	;# fetch the text of the page over http
	set page_content [http::data [http::geturl $url]]
;#	puts -nonewline "crawl_page debug 1, got content: \""
;#	puts $page_content
;#	puts "\"\n"
	
	;# look for url matches, store in url_list
	;# we will store these so we know what's been indexed and also use them to make recursive calls
	set url_list [regexp -all -inline $url_regex $page_content]
	set crawl_url_list [regexp -all -inline $crawl_url_regex $page_content]
	
	;# remove redundancy from the url lists
	set url_list [lsort -unique $url_list]
	set crawl_url_list [lsort -unique $crawl_url_list]
	
	puts "crawl_page debug 2, found urls :"
	for {set n 0} {$n<[llength $url_list]} {incr n} {
		puts "[lindex $url_list $n]"
	}
	
	;# TODO: look through the page text for anything matching index_regex
	;# and store what's found as appropriate (full names, email addresses, phone numbers, etc.)
	
	;# shuffle the crawl urls so that the order to crawl in isn't easily determined and changes
	for {set n 0} {$n<[llength $crawl_url_list]} {incr n} {
		set swap_pos_0 $n
		set swap_pos_1 [expr {int(([llength $crawl_url_list]-$n)*rand())+$n}]
		
		set swap_data [lindex $crawl_url_list $swap_pos_1]
		lset crawl_url_list $swap_pos_1 [lindex $crawl_url_list $swap_pos_0]
		lset crawl_url_list $swap_pos_0 $swap_data
	}
	
	;# take the urls found in the page text and recurse with them!
	for {set n 0} {$n<[llength $crawl_url_list]} {incr n} {
		;# check if this host is blacklisted
		set host_blacklist_check 0
		for {set blacklist_index 0} {$blacklist_index<[llength $host_blacklist]} {incr blacklist_index} {
			;# TODO: check based on domain, not just text anywhere in url
			if {[st_search [lindex $crawl_url_list $n] [lindex $host_blacklist $blacklist_index]]>=0} {
				set host_blacklist_check 1
			}
		}
		
		;# if we're already at the page to crawl skip to the next url
		if {[string equal [lindex $crawl_url_list $n] $url] || $host_blacklist_check} {
			continue
		}
		
		;# (after waiting a random amount of time so as to appear "human" when browsing)
		set sleep_time [expr {int(17*rand())}]
		puts "wating $sleep_time seconds before the next crawl to appear human..."
		
		after [expr {$sleep_time*1000}]
		
		;# if the recursion failed return a failure code up
		if {[crawl_page [lindex $crawl_url_list $n] $index_regex]!=1} {
			return 0
		}
		;# if it succeeded then go on to the next url
		;# (next iteration of the for loop)
	}
	
	;# NOTE: we're using 1 to mean true
	return 1
}


;# runtime entry point; main
proc main {argc argv argv0} {
	;# the url to start crawling from
	set start_url {}
	
	;# if we got an argument from the user, start there
	if {$argc>0} {
		set start_url [lindex $argv 0]
	} else {
		;# TODO: check all the urls on file 
		;# and re-index existing pages based on the current time and last index time
	}
	
	;# if the starting url is invalid then just give up
	if {[string length start_url]==0} {
		return 1
	}
	
	;# if we got here and didn't return, start crawling!
	;# TODO: add regexes to search for here
	crawl_page $start_url {}
}

;# runtime!
main $argc $argv $argv0


