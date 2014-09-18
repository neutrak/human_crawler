#!/bin/bash

#this makes random searches to google and reddit then crawls through the results
#I hope to extend this to other websites (news sites, etc.) in the future

query_starts=("https://www.google.com/#q=", "https://www.reddit.com/search?q=")

IFS='
'
read -d '' -r -a dict < /usr/share/dict/words
unset IFS

#echo ${dict[@]}

while [ 1 ]
do
	query_string="${query_starts[$(($RANDOM%${#query_starts[@]}))]}"
	
	num_words=$(($RANDOM%4+1))
	for n in $(seq 0 $num_words)
	do
		words_in_dict=${#dict[@]}
		word_idx=$((${RANDOM}%${words_in_dict}))
		
		#echo "Adding word ${dict[$word_idx]} to query..."
		
		query_string="${query_string}${dict[$word_idx]}"
		if [ $n -lt $num_words ]
		then
			query_string="${query_string}+"
		fi
	done
	
	echo "calling out to crawler.tcl with query ${query_string} ..."
	./crawler.tcl "${query_string}" 2 0.1
	
	sleep 2
done


