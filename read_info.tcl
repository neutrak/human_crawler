#!/usr/bin/tclsh8.6

;# a command-line tool to read the output of the crawler

;# read information from the given file and output it prettily
;# we store in plain text, the url then tcl lists of everything we parse out
;# returns true (1) on success, false (0) on failure
proc read_info {info_file desired_field} {
	;# initialize a blank content array
	set info_file_content [list]
	
	;# if the file is there to read, then read it into the content list
	if {[file exists $info_file]} {
		;# first get out the existing content
		set file_pointer [open $info_file {r}]
		
		;# TODO: should we ignore blank entries here? remove them or something? they're never written back to the file anyway...
		set info_file_content [split [read $file_pointer] "\n"]
		close $file_pointer
	;# if the file isn't there exit with error
	} else {
		return 0
	}
	
	;# this is a copy of the code that stores newly-crawled pages, for reference
	;# leave it commented out
;#	set timestamp [clock seconds]
;#	set current_info_line "$url $timestamp"
;#	append current_info_line " {$url_list}"
;#	append current_info_line " {$email_list}"
;#	append current_info_line " {$phone_num_list}"
	
	;# TODO: implement the parsing of these files so I can see what's in them!
	puts "read_info not yet implemented!"
;#	for {set n 0} {$n<[llength $info_file_content]} {incr n} {
;#		
;#	}
	
	return 1
}


;# runtime entry point
proc main {argc argv argv0} {
	if {$argc<2} {
		puts "Usage: $argv0 <file to check contents of> <desired information (email, phone_num, etc.)>"
		exit 0
	}
	
	;# if there was an error report it
	if {![read_info [lindex $argv 0] [lindex $argv 1]]} {
		puts "Err: Could not read info (does the file exist?)"
	}
}

;#runtime!
main $argc $argv $argv0


