#!/usr/bin/tclsh8.6

;# a command-line tool to read the output of the crawler

;# read information from the given file and output it prettily
;# we store in plain text, the url then tcl lists of everything we parse out
;# returns true (1) on success, false (0) on failure
proc read_info {info_file desired_field_index} {
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
	
	
	;# go through every line and print out the relevant data the user asked for
	for {set line_idx 0} {$line_idx<[llength $info_file_content]} {incr line_idx} {
		set line_data [lindex $info_file_content $line_idx]
		
		;#skip blank lines
		if {$line_data=={}} {
			continue
		}
		
		;# store the line as a list for easy access
		set line_list [list]
		
		;# how many {} sets we're nestled in
		set nest_level 0
		
		;# an accumulator string that must persist between loop iterations
		set acc_string {}
		
		;# go through the line and collect all the relevant data
		for {set n 0} {$n<[string length $line_data]} {incr n} {
			;# if we've reached the end of an element, put it in the larger structure
			if {($nest_level==0) && ([string index $line_data $n]=={ })} {
				lappend line_list $acc_string
				set acc_string {}
			;# if we've hit a delimiter record that
			} elseif {[string index $line_data $n]=="\{"} {
				incr nest_level
			} elseif {[string index $line_data $n]=="\}"} {
				incr nest_level -1
			;# otherwise this is part of the data, not control
			} else {
				append acc_string [string index $line_data $n]
			}
		}
		
		;# the last element got no delimiter because it reached end of data, so add it now
		if {$nest_level==0} {
			lappend line_list $acc_string
			set acc_string {}
		}
		
		;# if this was parsed more-or-less correctly
		if {[llength $line_list]>4} {
			;# get out all the data the user could ask for from the newly-parsed list
			puts [lindex $line_list $desired_field_index]
		} else {
			puts "Err: Could not parse $line_data"
		}
	}
	
	return 1
}


;# runtime entry point
proc main {argc argv argv0} {
	if {$argc<2} {
		puts "Usage: $argv0 <file to check contents of> <desired information (email, phone_num, etc.; direct index may also be used)>"
		exit 0
	}
	
	;# map words arguments onto field indices
	if {[lindex $argv 1]=={email}} {
		lset argv 1 3
	} elseif {[lindex $argv 1]=={phone_num}} {
		lset argv 1 4
	}
	
	;# if there was an error report it
	if {![read_info [lindex $argv 0] [lindex $argv 1]]} {
		puts "Err: Could not read info (does the file exist?)"
	}
}

;#runtime!
main $argc $argv $argv0


