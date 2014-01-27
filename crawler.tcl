#!/usr/bin/tclsh8.6

;# human-looking webcrawler, in tcl

set version {0.1}

package require TclCurl

;# NOTE: we're using 1 to mean true and 0 to mean false
;# not sure if this is how TCL does it, but it's our convention

;# TODO: I've noticed myself over-using regexes; in cases where it's not appropriate we really shouldn't use them at all

;# a regular expression to detect all urls in the text
set url_regex {https?://(?:[a-zA-Z0-9\-_()\%]+\.)+[a-zA-Z0-9\-_()\%]+(?:/[a-zA-Z0-9\-_?&=:\./;()\%]+)*}

;# TODO crawl urls that reference other pages on the same site (relative urls) also
;# I think if I add an @ sign in the accepted urls I can get mailto links but I'll have to parse that out too so for the moment I'm not
;#set relative_tagged_url_regex {(?:(?:href=[\"\']*)|(?:src=[\"\']*))[a-zA-Z0-9\-_?&=:\./;()%\"\']+[\"\']*}
set relative_tagged_url_regex {(?:(?:href=[\"\']*)|(?:src=[\"\']*))[a-zA-Z0-9\-_?&=:\./;%\"\']+[\"\']*}

;# a regular expression to detect all email addresses in the text
set email_regex {[a-zA-Z0-9\-_\.()]+@(?:[a-zA-Z0-9\-_]+\.)+[a-zA-Z0-9\-_]+}

;# a regex for phone numbers (do we need this?)
;# set phone_num_regex {[0-9]?\-\ ?(?:[0-9()]{3})?[\-\ ]?[0-9]{3}[\-\ ]?[0-9]{4}}

;# below is a phone number regex someone on stackoverflow suggested but I'm not sure what regex format it's in (perl?)
;# ^(?:(?:\+?1\s*(?:[.-]\s*)?)?(?:\(\s*([2-9]1[02-9]|[2-9][02-8]1|[2-9][02-8][02-9])\s*\)|([2-9]1[02-9]|[2-9][02-8]1|[2-9][02-8][02-9]))\s*(?:[.-]\s*)?)?([2-9]1[02-9]|[2-9][02-9]1|[2-9][02-9]{2})\s*(?:[.-]\s*)?([0-9]{4})(?:\s*(?:#|x\.?|ext\.?|extension)\s*(\d+))?$

;# a list of hosts /not/ to crawl
set host_blacklist [list {w3.org} {charter.net} {mediawiki.org} {google.com}]

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

;# find and remove matching quote mark in the history
;# returns the last occurance of current_char in the nest_chars list
proc remove_quote_match {nest_chars current_char} {
	;# find the matching quote mark
	set nest_to_leave [expr {[llength $nest_chars]-1}]
	while {$nest_to_leave>=0 && [lindex $nest_chars $nest_to_leave]!=$current_char} {
		incr nest_to_leave -1
	}
	
	;# this should never be false, but just in case... (people are bad at quote matching)
	;# if we found a matching mark
	if {$nest_to_leave>=0} {
		;# remove it from the nest_chars list
		set new_nest_chars [list]
		for {set nest_index 0} {$nest_index<[llength $nest_chars]} {incr nest_index} {
			if {$nest_index!=$nest_to_leave} {
				lappend new_nest_chars [lindex $nest_chars $nest_index]
			}
		}
		
		;# return the new nest_chars list, with that entry removed
		return $new_nest_chars
	}
	
	;# TODO: somehow mark this as an error? puts some error message?
	;# we got here and didn't return, that means there was nothing to match to, so idk what's going on
	return $nest_chars
}

;# check if a character qualifies as a quote mark
proc is_quote_mark {test_char} {
	if {($test_char=={'}) || ($test_char=="\"")} {
		return 1
	}
	return 0
}

;# returns true if this character is a valid delimiter for a phone number, else false
proc is_phone_delimiter {test_char} {
	if {($test_char=={'}) || ($test_char=="\"") || ($test_char=="\n") || ($test_char=={ })} {
		return 1
	}
	return 0
}

;# parse phone numbers in a much more reliable and simple way than with regular expressions
;# returns a list of phone numbers found in the given text
proc parse_phone_numbers {text} {
	;# the list of phone numbers to return
	set phone_num_list [list]
	
	;# our current nesting level within quotation marks
	set nest_level 0
	
	;# and a history of what chars were associated with each of the nesting levels
	set nest_chars [list]
	
	;# look through the text for a phone number
	for {set n 0} {$n<[string length $text]} {incr n} {
		;# a phone number is defined as a sequence of at least 7 digits and any amount of non-letter characters;
		;# delimeted by spaces, quotes, or newlines
		
		set this_number {}
		
		;# check for forward delimiter
		if {[is_phone_delimiter [string index $text $n]]} {
			
			set forward_delimiter [string index $text $n]
			
			;# don't consider the delimiter itself anymore
			incr n
			
			;# if the delimiter were quotes
			if {[is_quote_mark $forward_delimiter]} {
				;# if we just went into more quotes (either we weren't in any or the quote we hit didn't match the last one in the history)
				if {($nest_level<=0) || ([string index $text $n]!=[lindex $nest_chars [expr {[llength $nest_chars]-1}]])} {
					incr nest_level
					lappend nest_chars $forward_delimiter
;#					puts "nest_level=$nest_level, matching $forward_delimiter, nest_chars=$nest_chars"
				;# if we just got out of some quotes
				} else {
					;# we just got out of the old quotes, remember that and re-start from the start
					incr nest_level -1
					set nest_chars [remove_quote_match $nest_chars $forward_delimiter]
;#					puts "nest_level=$nest_level, matching $forward_delimiter, nest_chars=$nest_chars"
					
					continue
				}
			}
			
			;# eat all digits until backward delimiter (which must match the forward delimiter) is reached
			;# or we reach the end of text or an alphabet character
			while {($n<[string length $text]) && ($forward_delimiter!=[string index $text $n]) && (![string is alpha [string index $text $n]])} {
				
				;# store the parsed number in this_number
				if {[string is digit [string index $text $n]]} {
					set this_number "$this_number[string index $text $n]"
				}
				
				;# go to the next character
				incr n
			}
			
			;# exiting the loop means we hit a delimiter
			;# if this was a quote reduce the nest level
			if {[is_quote_mark [string index $text $n]]} {
				;# we just got out of the old quotes
				incr nest_level -1
				set nest_chars [remove_quote_match $nest_chars [string index $text $n]]
;#				puts "nest_level=$nest_level, matching $forward_delimiter, nest_chars=$nest_chars"
			}
		}
		
		;# if the number meets the length requirement, add it to the list at this time
		if {[string length $this_number]>=7} {
			lappend phone_num_list $this_number
		}
	}
	
	;# TODO: check list against known area codes and remove non-matching entries
	
	return $phone_num_list
}

;# END GENERAL HELPER FUNCTIONS

;# add (or update, if already existing) information about a url to the given file
;# we store in plain text, the url then tcl lists of everything we parse out
;#proc save_info {info_file url url_list email_list phone_num_list credit_num_list ssn_list} {
proc save_info {info_file url url_list email_list phone_num_list} {
	;# initialize a blank content array
	set info_file_content [list]
	
	;# if there's a file start with that instead
	if {[file exists $info_file]} {
		;# first get out the existing content
		set file_pointer [open $info_file {r}]
		
		;# TODO: should we ignore blank entries here? remove them or something? they're never written back to the file anyway...
		set info_file_content [split [read $file_pointer] "\n"]
		close $file_pointer
	}
	
	;# which line will be re-set with new info; or an error code if it's a new url
	set line_to_replace -1
	for {set n 0} {$n<[llength $info_file_content]} {incr n} {
		
		;# if this line started with the current url followed by a space, we're replacing that line
		if {[st_search [lindex $info_file_content $n] "$url "]==0} {
			;# remember that and break early
			set line_to_replace $n
			set n [llength $info_file_content]
		}
	}
	
	;# create the information line to store, and timestamp it too, like a good clerk
	set timestamp [clock seconds]
	set current_info_line "$url $timestamp"
	append current_info_line " {$url_list}"
	append current_info_line " {$email_list}"
	append current_info_line " {$phone_num_list}"
	
;#	set current_info_line "$url $timestamp $url_list $email_list $phone_num_list"
	
	;# if this is a new url add it at the end (we don't do sorting for the moment)
	if {$line_to_replace==-1} {
		lappend info_file_content $current_info_line
	;# we've indexed this before, update it
	} else {
		lset info_file_content $line_to_replace $current_info_line
	}
	
	;# TODO: be more efficient than re-writing the whole file each update; would a database make sense here?
	;# re-write the file with updated information
	set file_pointer [open $info_file {w}]
	for {set n 0} {$n<[llength $info_file_content]} {incr n} {
		;# if this line isn't blank
		if {[lindex $info_file_content $n]!={}} {
			
			;# write it to the file
			puts $file_pointer [lindex $info_file_content $n]
		}
	}
	close $file_pointer
}

;# a recursive function to crawl a web page, limited to a given depth because otherwise we'll never get back to the initial page
;# returns TRUE on success, FALSE on failure
proc crawl_page {url max_recursion_depth} {
	global url_regex
	global relative_tagged_url_regex
	global email_regex
	global phone_num_regex
	global host_blacklist
	
	puts "crawl_page debug 0, trying to crawl page $url, max_recursion_depth=$max_recursion_depth"
	
	;# the file name where we store the page we're currently crawling
	if {![file exists {data}]} {
		file mkdir {data}
	}
	set crawl_tmp_file [file join {data} {crawl_tmp.txt}]
	
	;#TODO: see if curl lets me set a user agent, I'd like to appear as a common browser (one of several, at random?)
	
	;# fetch the text of the page over http
	;# if there was error
	if {[curl::transfer -url $url -maxredirs 5 -file $crawl_tmp_file]!=0} {
		;# TODO: should this return an error? (it doesn't now)
		return 1
;#		return 0
	}
	set file_pointer [open $crawl_tmp_file {r}]
	set page_content [read $file_pointer [file size $crawl_tmp_file]]
	close $file_pointer
	
	;# this was from before the we switched to tclcurl; used the old http lib
;#	set page_content [http::data [http::geturl $url]]
	
	;# look for url matches, store in url_list
	;# we will store these so we know what's been indexed and also use them to make recursive calls
	;# the lsort -unique removes redundancy from the url list
	;# the concat serves to flatten the list
	set url_list [concat {*}[lsort -unique [regexp -all -inline $url_regex $page_content]]]
	set relative_tagged_url_list [concat {*}[lsort -unique [regexp -all -inline $relative_tagged_url_regex $page_content]]]
	
	;# the current domain (which gets prepended to relative ulrs)
	;# (a regex was probably overkill for this but I had one handy)
	regexp {https?://(?:[a-zA-Z0-9\-_()\%]+\.)+[a-zA-Z0-9\-_()\%]+} $url current_domain
	regexp {(?:[a-zA-Z0-9\-_()\%]+\.)+[a-zA-Z0-9\-_()\%]+} $url save_domain
	
	if {![file exists [file join {data} $save_domain]]} {
		file mkdir [file join {data} $save_domain]
	}
	
	for {set n 0} {$n<[llength $relative_tagged_url_list]} {incr n} {
		;# parse out the tags; this is a nasty hack but it ought to work 90% of the time
		set tagged_url [lindex $relative_tagged_url_list $n]
		
		;# this is for stripping away quotes so we only strip away quotes of a matching type, as the other type would be part of the url
		set quote_type {}
		
		;# strip off everything up to and including the first = sign
		set equal_index [st_search $tagged_url {=}]
		set tagged_url [st_substr $tagged_url [expr {$equal_index+1}] [expr {[string length $tagged_url]-$equal_index-[string length {=}]}]]
		
		;# strip off quote marks if they're there
		set tagged_url [string trim $tagged_url "\""]
		set tagged_url [string trim $tagged_url {'}]
		
		;# now prepend the current url's domain, if this url doesn't already start with "http"
		;# TODO: also account for sub-domain references
		if {[st_search $tagged_url "http"]!=0} {
			;# if it doesn't start with a slash give it one now
			if {[string index $tagged_url 0]!={/}} {
				set tagged_url "/$tagged_url"
			}
			
			;# if both characters were slashes prepend http, this is on a different host
			if {[st_search $tagged_url {//}]==0} {
				set tagged_url "http:$tagged_url"
			
			;# if the url didn't start with // then prepend the current domain, this is a relative url
			} else {
				set tagged_url "$current_domain$tagged_url"
			}
		}
		
		;# and save it back into the original structure!
		lset relative_tagged_url_list $n $tagged_url
	}
	
	;# append relative urls (with current domain prepended) to the url_list here
	for {set n 0} {$n<[llength $relative_tagged_url_list]} {incr n} {
		;# note that we may accidentally add some javascript here but at worst it'll 404 and I deem that acceptable
		lappend url_list [lindex $relative_tagged_url_list $n]
	}
	
	;# also re-checking for uniqueness and removing duplicates
	set url_list [concat {*}[lsort -unique $url_list]]
	
	;# look through the page text for anything matching email, phone, etc.
	set email_list [concat {*}[lsort -unique [regexp -all -inline $email_regex $page_content]]]
;#	set phone_num_list [concat {*}[lsort -unique [regexp -all -inline $phone_num_regex $page_content]]]
	set phone_num_list [parse_phone_numbers $page_content]
	
	puts "crawl_page debug 1: found [llength $url_list] url(s), [llength $email_list] email addresse(s), [llength $phone_num_list] phone number(s)" 
	
	;# store what's found as appropriate (full names, email addresses, phone numbers, etc.)
	save_info [file join {data} $save_domain {scraped_data.txt}] $url $url_list $email_list $phone_num_list
	
	;# shuffle the urls so that the order to crawl in isn't easily determined and changes with each run
	for {set n 0} {$n<[llength $url_list]} {incr n} {
		set swap_pos_0 $n
		set swap_pos_1 [expr {int(([llength $url_list]-$n)*rand())+$n}]
		
		set swap_data [lindex $url_list $swap_pos_1]
		lset url_list $swap_pos_1 [lindex $url_list $swap_pos_0]
		lset url_list $swap_pos_0 $swap_data
	}
	
	;# put all the image, css, and javascript urls at the start of the url list, with the favicon.ico at the very top if there is one
	;# because we know a real boy (browser) would load all images before going elsewhere
	;# also maybe eliminate the waits for those?
	
	;# initialize a blank url list, which will get copied from the already parsed one after it's re-arranged (below)
	set new_url_list [list]
	set copied_url_indices [list]
	
	;# a list of extensions indicating a higher priority
	set priority_extensions [list {.css} {.js} {.ico} {.png} {.jpg} {.jpeg} {.gif} {.bmp}]
	
	;# first copy over everything with a high priority extension into a new url list
	for {set ext_index 0} {$ext_index<[llength $priority_extensions]} {incr ext_index} {
		for {set url_index 0} {$url_index<[llength $url_list]} {incr url_index} {
			
			;# if this url ends with one of the given file extensions
			if {[string last [lindex $priority_extensions $ext_index] [string tolower [lindex $url_list $url_index]]]==[expr {[string length [lindex $url_list $url_index]]-[string length [lindex $priority_extensions $ext_index]]}]} {
				
				lappend new_url_list [lindex $url_list $url_index]
				lappend copied_url_indices $url_index
			}
		}
	}
	set crawls_before_wait [llength $new_url_list]
	
	;# then copy over everything with a regular/low priority
	for {set url_index 0} {$url_index<[llength $url_list]} {incr url_index} {
		set already_copied 0
		for {set n 0} {$n<[llength $copied_url_indices]} {incr n} {
			if {$url_index==[lindex $copied_url_indices $n]} {
				set already_copied 1
			}
		}
		
		if {!$already_copied} {
			lappend new_url_list [lindex $url_list $url_index]
		}
	}
	
	;# and finally save it back to our old variable
	set url_list $new_url_list
;#	puts "crawl_page debug 2; found [llength $url_list] urls, of which $crawls_before_wait are high-priority"
	
	;# take the urls found in the page text and recurse with them!
	for {set n 0} {$n<[llength $url_list]} {incr n} {
		;# check if this host is blacklisted
		set host_blacklist_check 0
		for {set blacklist_index 0} {$blacklist_index<[llength $host_blacklist]} {incr blacklist_index} {
			;# TODO: check based on domain, not just text anywhere in url
			if {[st_search [lindex $url_list $n] [lindex $host_blacklist $blacklist_index]]>=0} {
				set host_blacklist_check 1
			}
		}
		
		;# if we're already at the page to crawl skip to the next url
		if {[string equal [lindex $url_list $n] $url] || $host_blacklist_check} {
			continue
		}
		
		;# if we hit our recursion limit give up and return
		if {$max_recursion_depth<=0} {
			break
		}
		
		;# if this isn't a high-priority request, then wait
		if {$n>=$crawls_before_wait} {
			;# (after waiting a random amount of time so as to appear "human" when browsing)
			set sleep_time [expr {int(17*rand())}]
			puts "wating $sleep_time seconds before the next crawl to appear human..."
			
			after [expr {$sleep_time*1000}]
			
			;# have a 4% chance of waitng longer
			if {[expr {int(rand()*100)<4}]} {
				puts "doing long wait as if the user stopped browsing..."
				after [expr {75*1000}]
				
				;# I'm not 100% sure this is desired behavior but it'll do for now
				;# break the loop here and return up as if the user started from a higher-up position
	;#			return 1
			}
		}
		
		;# if the recursion failed return a failure code up
		if {[crawl_page [lindex $url_list $n] [expr {$max_recursion_depth-1}]]!=1} {
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
	set max_recursion_depth 10
	
	;# if we got an argument from the user, start there
	if {$argc>0} {
		set start_url [lindex $argv 0]
		if {$argc>1} {
			set max_recursion_depth [lindex $argv 1]
		}
	} else {
		puts "no url to crawl given..."
		
		;# TODO: check all the urls on file, instead of just returning/exiting
		;# and re-index existing pages based on the current time and last index time
		
		return 0
	}
	
	;# if the starting url is invalid then just give up
	if {[string length start_url]==0} {
		return 1
	}
	
	;# if we got here and didn't return, start crawling!
	crawl_page $start_url $max_recursion_depth
}

;# runtime!
main $argc $argv $argv0

;# tests

;#puts [parse_phone_numbers { 56823490823 this is' a test\"''\"' '687-0987' \"12345657567567\" \"123\" '825-6543' "874/8.828"}]

