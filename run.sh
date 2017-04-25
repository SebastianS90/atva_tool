#!/bin/bash

#set this to root of your Pin directory"
PIN_DIR="/home/sumanth/cmi/thesis/pin/pin-3.2-81205-gcc-linux/"
#set this to path where we can find cbmc binary"
CBMC_DIR="."
#maximum time allowed for a command
MAX_TIME=200
#exit statuses of CBMC
CBMC_SAFE_STATUS=0
CBMC_UNSAFE_STATUS=10
#number of runs of input program under pin tool
PIN_RUNS=10

CBMC=$CBMC_DIR"/cbmc"
PIN=$PIN_DIR"/pin"
TIMEOUT="timeout --preserve-status -k 3 $MAX_TIME"
TRACE_SO="./trace.so"
PARSE_BIN="./parse"


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

#requires $PIN_DIR, $TRACE_SO, $PARSE_BIN to be set
function compile_pin_tool()
{
    print_debug "compiling $TRACE_SO"
    
        g++ -ggdb -DBIGARRAY_MULTIPLIER=1 -Wall -Werror -Wno-unknown-pragmas -D__PIN__=1 -DPIN_CRT=1 -fno-stack-protector -fno-exceptions \
	-funwind-tables -fasynchronous-unwind-tables -fno-rtti -DTARGET_IA32E -DHOST_IA32E -fPIC -DTARGET_LINUX -fabi-version=2  \
	-I $PIN_DIR/source/include/pin -I $PIN_DIR/source/include/pin/gen -isystem $PIN_DIR/extras/stlport/include -isystem $PIN_DIR/extras/libstdc++/include \
	-isystem $PIN_DIR/extras/crt/include -isystem $PIN_DIR/extras/crt/include/arch-x86_64 -isystem $PIN_DIR/extras/crt/include/kernel/uapi -isystem \
	$PIN_DIR/extras/crt/include/kernel/uapi/asm-x86 -I $PIN_DIR/extras/components/include -I $PIN_DIR/extras/xed-intel64/include/xed \
	-I $PIN_DIR/source/tools/InstLib -O3 -fomit-frame-pointer -fno-strict-aliasing   -c -o trace.o trace.cpp

    if [ $? -ne 0 ]; then
	exit
    fi
   
    g++ -ggdb -shared -Wl,--hash-style=sysv $PIN_DIR/intel64/runtime/pincrt/crtbeginS.o -Wl,-Bsymbolic \
	-Wl,--version-script=$PIN_DIR/source/include/pin/pintool.ver -fabi-version=2    \
	-o $TRACE_SO  trace.o  -L$PIN_DIR/intel64/runtime/pincrt \
	-L$PIN_DIR/intel64/lib -L$PIN_DIR/intel64/lib-ext -L$PIN_DIR/extras/xed-intel64/lib -lpin -lxed \
	$PIN_DIR/intel64/runtime/pincrt/crtendS.o -lpin3dwarf  -ldl-dynamic -nostdlib -lstlport-dynamic \
	-lm-dynamic -lc-dynamic -lunwind-dynamic

    if [ $? -ne 0 ]; then
	exit
    fi

    print_debug "compiled $TRACE_SO"
    
    #compile parse file
    g++ -ggdb -o $PARSE_BIN parse.cpp

    if [ $? -ne 0 ]; then
	exit
    fi
    
    print_debug "compiled $PARSE_BIN"
}

#decodes address to line number and variable using gdb
#requires $defuse, $inputBin, $defuse_cbmc
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
    echo "Or run.sh [-u unwind_count] file_with_list_of_files"
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
    fi
    
    unwindc1=`echo $line1 | cut -d' ' -f2`
    if [[ -z $unwindc && -z $unwindc1 ]]; then
	print_info "Skipping $inputFile"
	print_info "Either provide -u unwind_count or unwind_count for $inputFile in $fileList."
	continue;
    elif [ -z $unwindc ]; then
	unwindc=$unwindc1
    fi
    
    run_file
    
done < $fileList
   
echo "Following files failed compilation: "
echo $compileFailFiles	    
