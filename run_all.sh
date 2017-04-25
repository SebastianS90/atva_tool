#!/bin/bash


#path to PIN tool
PIN="/home/sumanth/cmi/thesis/pin/pin-3.2-81205-gcc-linux/pin"
#path to CBMC with refinement implementation
ENCODED_CBMC="./cbmc"
#path to vanilla CBMC
PLAIN_CBMC="/home/sumanth/cmi/thesis/cbmc/src/cbmc/cbmc"
#maximum timeout for a command
MAX_TIME=200

#decodes address to line number and variable
decode()
{
    output=""
    line=""
    print_debug "decoding address to line from $defuse to $defuse_cbmc"
    while read line; do
	arr=($line)
	if [[ ${arr[0]} =~ ^# ]]
	then
	    break
	fi
	#each line is of the form: variable_addr read_ins_addr #writes (write_ins_addr)+
	for (( i=0; i<$(( ${#arr[*]} )); i++))
	do
	    if [ $i -ne 0 ] && [ $i -ne 2 ]; then
		 #address to line number
		output=$output`gdb -batch -ex "file $inputBin" -ex "info line *${arr[$i]}" | cut -d' ' -f2`
		output=$output" "
	    elif [ $i -eq 0 ]; then
		#variable_addr to variable_name
		output=$output`gdb -batch -ex "file $inputBin" -ex "info symbol ${arr[$i]}" | cut -d' ' -f1`
		output=$output" "
	    elif [ $i -eq 2 ]; then 
		#number of writes
		output=$output${arr[$i]}
		output=$output" "
	    fi
	done
	output="$output\n"
	#echo >> $invFile
    done < $defuse
    echo -n -e $output > $defuse_cbmc
}


function run_plain_cbmc()
{
    print_debug "$TIMEOUT $PLAIN_CBMC --unwind $unwindc $inputExt > $plain_cbmc_output"
    
    $TIMEOUT $PLAIN_CBMC --unwind $unwindc $inputExt > $plain_cbmc_output
    exit_status=$?
    if [ $exit_status -eq $CBMC_SAFE_STATUS ]; then
	timeTaken=`grep "$PLAIN_CBMC_TIME_MSG" $plain_cbmc_output | cut -d':' -f2`
	cbmcResult=$cbmcResult"|safe|$timeTaken|-|"
    elif [ $exit_status -eq $CBMC_UNSAFE_STATUS ]; then
	timeTaken=`grep "$PLAIN_CBMC_TIME_MSG" $plain_cbmc_output | cut -d':' -f2`
	cbmcResult=$cbmcResult"|unsafe|$timeTaken|-|"
    else
	timeTaken=" > $MAX_TIME"
	cbmcResult=$cbmcResult"|timeout|$timeTaken|FIXME|"
    fi
}

function run_inv_cbmc()
{
    print_debug "$TIMEOUT $ENCODED_CBMC --unwind $unwindc --refine-cpu --invariant-strategy l --invariant-file $defuse_cbmc $inputExt > $inv_cbmc_output"
    
    $TIMEOUT $ENCODED_CBMC --unwind $unwindc --refine-cpu --invariant-strategy l --invariant-file $defuse_cbmc $inputExt > $inv_cbmc_output
    exit_status=$?
    if [ $exit_status -eq $CBMC_SAFE_STATUS ]; then
	timeTaken=`grep "$ENC_CBMC_TIME_MSG" $inv_cbmc_output | cut -d':' -f2`
	refinement=`grep "CPU_REFINEMENT_END" $inv_cbmc_output | cut -d':' -f2`
	invResult=$invResult"|safe|$timeTaken|$refinement|"
    elif [ $exit_status -eq $CBMC_UNSAFE_STATUS ]; then
	timeTaken=`grep "$ENC_CBMC_TIME_MSG" $inv_cbmc_output | cut -d':' -f2`
	refinement=`grep "CPU_REFINEMENT_END" $inv_cbmc_output | cut -d':' -f2`
	invResult=$invResult"|unsafe|$timeTaken|$refinement|"
    else
	timeTaken=" > $MAX_TIME"
	invResult=$invResult"|timeout|$timeTaken|FIXME timeout|"
    fi
}

function run_arb_cbmc()
{
    print_debug "$TIMEOUT $ENCODED_CBMC --unwind $unwindc --refine-cpu --invariant-strategy a $inputExt > $arb_cbmc_output"
    
    $TIMEOUT $ENCODED_CBMC --unwind $unwindc --refine-cpu --invariant-strategy a $inputExt > $arb_cbmc_output
    exit_status=$?
    if [ $exit_status -eq $CBMC_SAFE_STATUS ]; then
	timeTaken=`grep "$ENC_CBMC_TIME_MSG" $arb_cbmc_output | cut -d':' -f2`
	refinement=`grep "CPU_REFINEMENT_END" $arb_cbmc_output | cut -d':' -f2`
	arbResult=$arbResult"|safe|$timeTaken|$refinement|"
    elif [ $exit_status -eq $CBMC_UNSAFE_STATUS ]; then
	timeTaken=`grep "$ENC_CBMC_TIME_MSG" $arb_cbmc_output | cut -d':' -f2`
	refinement=`grep "CPU_REFINEMENT_END" $arb_cbmc_output | cut -d':' -f2`
	arbResult=$arbResult"|unsafe|$timeTaken|$refinement|"
    else
	timeTaken=" > $MAX_TIME"
	arbResult=$arbResult"|timeout|$timeTaken|FIXME timeout|"
    fi
}

function update_tables()
{
    cbmcResult=$cbmcResult"gain|\n"
    invResult=$invResult":::|\n"
    arbResult=$arbResult":::|\n"
    
    table1=$table1$cbmcResult$invResult
    table2=$table2$cbmcResult$arbResult
    table3=$table3$cbmcResult$invResult$arbResult
}

function print_tables()
{
    resultFile=$logBaseDir"/result"
    echo -e $table1 | tee -a $resultFile
    echo -e $table2 | tee -a $resultFile
    echo -e $table3 | tee -a $resultFile
}

function print_debug()
{
    echo "DEBUG: " $1
}

function print_err()
{
    echo "ERROR: " $1
    exit
}

if [ $# -eq 1 ]; then
    fileList=$1
elif [ $# -eq 2 ]; then
    fileList=$1
    unwindc=$2
else
    print_err "Usage: ./run_all.sh file(which has list of files) unwind_count"
fi    

    

#unwindc=$2

PIN_RUNS=10
CBMC_SAFE_STATUS=0
CBMC_UNSAFE_STATUS=10

TIMEOUT="timeout --preserve-status -k 3 $MAX_TIME"

TRACE_SO="trace.so"
PARSE_BIN="./parse"

ENC_CBMC_TIME_MSG="Runtime decision procedure"
PLAIN_CBMC_TIME_MSG="Runtime decision procedure"

logBaseDir="log_"`date +"%Y%m%d%H%M"`
mkdir $logBaseDir

table1="^File ^Result ^Decision Time ^Refinement ^Gain^\n "
table2=$table1
table3=$table2


while read line1; do
    inputFull=`echo $line1 | cut -d' ' -f1`
    if [[ -z $inputFull || ! -f $inputFull ]]; then
	print_debug "Skipping \"$line1\"."
    fi
    
    unwindc1=`echo $line1 | cut -d' ' -f2`
    if [[ -z $unwindc && -z $unwindc1 ]]; then
	print_info "Skipping $inputFile"
	print_info "Either provide -u unwind_count or unwind_count for $inputFile in $fileList."
	continue;
    elif [ -z $unwindc ]; then
	unwindc=$unwindc1
    fi
    
    input=`basename ${inputFull%.*}`
    inputExt=`basename ${inputFull}`

    logDir=$logBaseDir"/"$input
    rm -r $logDir
    mkdir $logDir
    cp $inputFull $logDir"/"
    inputBin=$logDir"/"$input".out"
    inputExt=$logDir"/"$inputExt

    print_debug "gcc -ggdb -o $inputBin $inputExt verifier.c -lpthread"
    gcc -ggdb -o $inputBin $inputExt verifier.c -lpthread
    if [ $? -ne 0 ]; then
	compileFailFiles="$inputExt\n"$compileFailFiles
	continue;
    fi

    cbmcResult="|"$input".c"
    invResult="|:::"
    arbResult="|:::"

    traces=$logDir"/trace"
    defuse=$logDir"/defuse"
    defuse_cbmc=$logDir"/defuse_cbmc"

    plain_cbmc_output=$logDir"/plain_cbmc_output"
    inv_cbmc_output=$logDir"/inv_cbmc_output"
    arb_cbmc_output=$logDir"/arb_cbmc_output"
    
    pin_success=1
    for ((i=1; i<=$PIN_RUNS; i++)); do
	print_debug "pin iteration $i"
	$TIMEOUT $PIN -t $TRACE_SO -- $inputBin >> $traces
	pinStatus=$?
	if [ $pinStatus -ne 0 ]; then
	    print_debug "pin exited with $pinStatus for $inputBin" >> $inv_cbmc_output
	    #NOTE: irrespective of pin success we continue with getting invariants
	    #NOTE: to avoid it uncomment below code
#	    pin_success=0
#	    invResult=$invResult"|unsafe|-|program assert|"
#	    run_plain_cbmc
#	    run_arb_cbmc
#	    update_tables
#	    print_tables
#	    break
	fi
    done

#    if [ $pin_success -ne 1 ]; then
#	continue
#    fi
    
    $PARSE_BIN $traces > $defuse
    if [ $? -ne 0 ]; then
	print_debug "parse failed for $inputExt"
	parseSuccess=0
	invResult=$invResult"|-|-|FIXME parse failed|"
	run_plain_cbmc
	run_arb_cbmc
	update_tables
	print_tables
	continue
    fi

    decode
    
    run_inv_cbmc

    run_arb_cbmc

    run_plain_cbmc

    update_tables

    print_tables
    
done < $fileList

#print_tables

echo -e "compile failed files: "$compileFailFiles
