#!/usr/bin/tclsh8.6

;# human-looking webcrawler, in tcl

set version {0.1}

package require TclCurl

;# NOTE: we're using 1 to mean true and 0 to mean false
;# not sure if this is how TCL does it, but it's our convention

;# a regular expression to detect all urls in the text
set url_regex {https?://(?:[a-zA-Z0-9\-_]+\.)+[a-zA-Z0-9\-_]+(?:/[a-zA-Z0-9\-_?&=:./;]+)*}

;# TODO crawl urls that reference other pages on the same site (relative urls) also
set relative_url_regex {}

;# a regular expression to detect all email addresses in the text
set email_regex {[a-zA-Z0-9\-_\.()]+@(?:[a-zA-Z0-9\-_]+\.)+[a-zA-Z0-9\-_]+}

;# a regex for phone numbers
set phone_num_regex {[0-9]?\-\ ?(?:[0-9()]{3})?[\-\ ]?[0-9]{3}[\-\ ]?[0-9]{4}}

;# a list of hosts /not/ to crawl
set host_blacklist [list {w3.org} {charter.net} {mediawiki.org}]

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
		puts $file_pointer [lindex $info_file_content $n]
	}
	close $file_pointer
}

;# a recursive function to crawl a web page, limited to a given depth because otherwise we'll never get back to the initial page
;# returns TRUE on success, FALSE on failure
proc crawl_page {url max_recursion_depth} {
	global url_regex
	global email_regex
	global phone_num_regex
	global host_blacklist
	
	puts "crawl_page debug 0, trying to crawl page $url, max_recursion_depth=$max_recursion_depth"
	
	;# the file name where we store the page we're currently crawling
	if {![file exists {data}]} {
		file mkdir {data}
	}
	set crawl_tmp_file [file join {data} {crawl_tmp.txt}]
	
	;# fetch the text of the page over http
	set curl_handle [curl::init]
	;# if there was error
	if {[curl::transfer -url $url -maxredirs 5 -file $crawl_tmp_file]!=0} {
		$curl_handle cleanup
		;# TODO: should this return an error? (it doesn't now)
;#		return 1
		return 0
	}
	set file_pointer [open $crawl_tmp_file {r}]
	set page_content [read $file_pointer [file size $crawl_tmp_file]]
	close $file_pointer
	
;#	set page_content [http::data [http::geturl $url]]
	
;#	puts -nonewline "crawl_page debug 1, got content: \""
;#	puts $page_content
;#	puts "\"\n"
	
	;# look for url matches, store in url_list
	;# we will store these so we know what's been indexed and also use them to make recursive calls
	;# the lsort -unique removes redundancy from the url list
	;# the concat serves to flatten the list
	set url_list [concat {*}[lsort -unique [regexp -all -inline $url_regex $page_content]]]
	
	;# TODO: append relative urls (with current domain prepended) to the url_list here
	
	;# look through the page text for anything matching email, phone, etc.
	set email_list [concat {*}[lsort -unique [regexp -all -inline $email_regex $page_content]]]
	set phone_num_list [concat {*}[lsort -unique [regexp -all -inline $phone_num_regex $page_content]]]
	
;#	puts "crawl_page debug 2, found urls :"
;#	for {set n 0} {$n<[llength $url_list]} {incr n} {
;#		puts "[lindex $url_list $n]"
;#	}
;#	puts "crawl_page debug 3, found emails :"
;#	for {set n 0} {$n<[llength $email_list]} {incr n} {
;#		puts "[lindex $email_list $n]"
;#	}
;#	puts "crawl_page debug 4, found phone numbers :"
;#	for {set n 0} {$n<[llength $phone_num_list]} {incr n} {
;#		puts "[lindex $phone_num_list $n]"
;#	}
	
	puts "crawl_page debug 5: found [llength $url_list] urls, [llength $email_list] email addresses, [llength $phone_num_list] phone numbers" 
	
	;# store what's found as appropriate (full names, email addresses, phone numbers, etc.)
	save_info [file join {data} {scraped_data.txt}] $url $url_list $email_list $phone_num_list
	
	;# shuffle the urls so that the order to crawl in isn't easily determined and changes with each run
	for {set n 0} {$n<[llength $url_list]} {incr n} {
		set swap_pos_0 $n
		set swap_pos_1 [expr {int(([llength $url_list]-$n)*rand())+$n}]
		
		set swap_data [lindex $url_list $swap_pos_1]
		lset url_list $swap_pos_1 [lindex $url_list $swap_pos_0]
		lset url_list $swap_pos_0 $swap_data
	}
	
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
			return 1
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
		
		;# TODO: check all the urls on file 
		;# and re-index existing pages based on the current time and last index time
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


