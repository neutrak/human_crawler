#!/usr/bin/tclsh8.5

;# human-looking webcrawler, in tcl

set version {0.1}

package require http


;# NOTE: we're using 1 to mean true and 0 to mean false
;# not sure if this is how TCL does it, but it's our convention

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
	puts "crawl_page debug 0, trying to crawl page $url"
	
;# this section parses out the domain from the url, but I don't think we need it
;# the http library should accomplish this
if {0} {
	;# the host to ask for the page, pulled from the url
	;# initialized empty
	set domain {}
	
	;# TODO: add more TLDs to the list we consider
	set tlds [list {.com} {.org} {.net} {.edu} {.co.uk} {.ca} {.hu} {.de}]
	for {set n 0} {$n<[llength $tlds]} {incr n} {
		set tld_index [st_search $url [lindex $tlds $n]]
		
		;# if we found this tld
		if {$tld_index!=-1} {
			;# set the domain to the substring up to and including it
			set domain [st_substr $url 0 [expr {$tld_index+[string length [lindex $tlds $n]]}]]
			
			;#and break
			set n [llength $tlds]
		}
	}
}
	
	
	;# TODO: fetch the text of the page over http
	set page_content [http::data [http::geturl $url]]
	puts -nonewline "crawl_page debug 1, got content: \""
	puts $page_content
	puts "\"\n"
	
	;# TODO: look through the page text for anything matching index_regex
	;# and store what's found as appropriate (email addresses, urls, etc.)
	
	;# TODO: take the urls found in the page text and recurse with them!
	;# (after waiting a random amount of time so as to appear "human" when browsing)
	
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


