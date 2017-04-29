#!/bin/bash

source "./common"

CBMC=$CBMC_DIR"/cbmc"
PIN=$PIN_DIR"/pin"
TIMEOUT="timeout --preserve-status -k 3 $MAX_TIME"


single_file=0

function print_debug()
{
    echo "DEBUG: " $1
}

function print_info()
{
    echo "NOTE: " $1
}

function print_result()
{
    echo -e $resultOut
}

function print_err()
{
    echo "ERROR: " $1
    exit 1
}



#requires $TIMEOUT, $CBMC, $unwindc, $defuse_cbmc, $inputExt, $cbmcOut, $CBMC_SAFE_STATUS, $CBMC_UNSAFE_STATUS
function run_cbmc()
{

    print_debug "Running: $TIMEOUT $CBMC --unwind $unwindc --refine-cpu --invariant-strategy l --invariant-file $defuse_cbmc $inputExt > $cbmcOut"
    
    $TIMEOUT $CBMC --unwind $unwindc --refine-cpu --invariant-strategy l --invariant-file $defuse_cbmc $inputExt >> $cbmcOut
    exit_status=$?
    if [ $exit_status -eq $CBMC_SAFE_STATUS ]; then
	timeTaken=`grep "Runtime decision procedure" $cbmcOut | cut -d':' -f2`
	refinement=`grep "CPU_REFINEMENT_END" $cbmcOut | cut -d':' -f2`
	resultOut=$resultOut"|safe|$timeTaken|$refinement|\n"
    elif [ $exit_status -eq $CBMC_UNSAFE_STATUS ]; then
	timeTaken=`grep "Runtime decision procedure" $cbmcOut | cut -d':' -f2`
	refinement=`grep "CPU_REFINEMENT_END" $cbmcOut | cut -d':' -f2`
	resultOut=$resultOut"|unsafe|$timeTaken|$refinement|\n"
    else
	timeTaken=" > $MAX_TIME"
	resultOut=$resultOut"|timeout|$timeTaken|-|\n"
    fi
}


#requires $inputFile, $unwindc, $logBaseDir, $TIMEOUT, $PIN_RUNS
function run_file()
{
    input=`basename ${inputFile%.*}`
    inputExt=`basename ${inputFile}`

    logDir=$logBaseDir"/"$input
    rm -r $logDir
    mkdir $logDir
    cp $inputFile $logDir"/"
    inputBin=$logDir"/"$input".out"
    inputExt=$logDir"/"$inputExt

    print_debug "Running gcc -ggdb -o $inputBin $inputExt verifier.c -lpthread"
    #change here to add additional options
    gcc -ggdb -o $inputBin $inputExt verifier.c -lpthread
    if [ $? -ne 0 ]; then
	print_info "Compilation failed for $inputExt"
	compileFailFiles="$inputExt\n"$compileFailFiles
	return
    fi

    resultOut=$resultOut$input".c"

    traces=$logDir"/trace"
    defuse=$logDir"/defuse"
    defuse_cbmc=$logDir"/defuse_cbmc"

    cbmcOut=$logDir"/cbmc_output"
    
    for ((i=1; i<=$PIN_RUNS; i++)); do
	print_debug "pin iteration $i"
	$TIMEOUT $PIN -t $TRACE_SO -- $inputBin >> $traces
	pinStatus=$?
	if [ $pinStatus -ne 0 ]; then
	    print_debug "pin exited with $pinStatus for $inputBin" >> $cbmcOut
	fi
    done

    $PARSE_BIN $traces > $defuse
    if [ $? -ne 0 ]; then
	print_info "parse failed for $inputExt"
	resultOut=$resultOut"|-|-|-|\n"
	return
    fi

    decode
    
    run_cbmc

    print_result
}



function usage()
{
    echo "Usage: run.sh -f inputFile -u unwind_count"
    echo "Or run.sh file_with_list_of_files"
    exit 1
}

singleFile=0

while getopts ":f:u:" opt; do
    case "${opt}" in
	f)
	    singleFile=1
	    inputFile=${OPTARG}
	    #shift 2
	    ;;
	u)
	    unwindc=${OPTARG}
	    #shift 2
	    ;;
	*)
	    usage
	    ;;
    esac
done

shift $(($OPTIND - 1))

if [[ $singleFile -eq 0 && -z $1 ]]; then
    print_info "Either provide -f inputFile or file_with_list_of_files."
    usage
fi

if [[ $singleFile -eq 1 && ! -z $1 ]]; then
    print_info "Either provide -f inputFile or file_with_list_of_files."
    usage
fi

if [[ $singleFile -eq 1 && -z $unwindc ]]; then
    print_info "-u unwind_count missing!"
    usage
fi


fileList=$1

if [ ! -f $CBMC ]; then
    print_err "$CBMC not found!"
fi

if [ ! -f $PIN ]; then
    print _err "$PIN not found!"
fi

if [[ ! -f $TRACE_SO || ! -f $PARSE_BIN ]]; then
    compile_pin_tool
fi

logBaseDir="log_"`date +"%Y%m%d%H%M"`
mkdir $logBaseDir

resultOut="^File ^Result ^Decision Time ^Refinement^\n"

if [ $singleFile -eq 1 ]; then
    run_file
    #echo $resultOut
    exit 0
fi

while read line1; do
    inputFile=`echo $line1 | cut -d' ' -f1`
    if [[ -z $inputFile || ! -f $inputFile ]]; then
	print_info "Skipping \"$line1\"."
	continue
    fi
    
    unwindc=`echo $line1 | cut -d' ' -f2`
    if [ -z $unwindc ]; then
	print_info "Skipping $inputFile"
	print_info "unwind count is missing for $inputFile in $fileList."
	continue
    fi
    
    run_file
    
done < $fileList
   
echo "Following files failed compilation: "
echo $compileFailFiles	    
