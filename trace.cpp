/*BEGIN_LEGAL 
Intel Open Source License 

Copyright (c) 2002-2016 Intel Corporation. All rights reserved.
 
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.  Redistributions
in binary form must reproduce the above copyright notice, this list of
conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.  Neither the name of
the Intel Corporation nor the names of its contributors may be used to
endorse or promote products derived from this software without
specific prior written permission.
 
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE INTEL OR
ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
END_LEGAL */

#include <iostream>
#include <vector>
#include <string>
#include "pin.H"
#include <sstream>
//#include <set>
#include "macros.h"

using std::vector;
using std::cout;
using std::endl;
using std::pair;
using std::string;
//using std::set;

KNOB<string> KnobTraceFunctionList(KNOB_MODE_WRITEONCE, "pintool",
				      "f", "*", "list of functions to trace (comma separated)");

struct valuet {
  THREADID tid;
  bool op;
  ADDRINT addr;
  valuet(THREADID in_tid, bool in_op, ADDRINT in_addr) {
    tid = in_tid;
    op = in_op;
    addr = in_addr;
  }
  valuet() { }
};

//key(operand address) value pair
typedef pair<ADDRINT, valuet> entryt;
typedef vector<entryt> entriest;
entriest entries;
PIN_MUTEX entries_lock;

vector<string> tracefunctionlist;

void read_ins(THREADID tid, ADDRINT addr, ADDRINT ins) {
  PIN_MutexLock(&entries_lock);
  entries.push_back(entryt(ins, valuet(tid, READ, addr)));
  PIN_MutexUnlock(&entries_lock);
}

void write_ins(THREADID tid, ADDRINT addr, ADDRINT ins) {
  PIN_MutexLock(&entries_lock);
  entries.push_back(entryt(ins, valuet(tid, WRITE, addr)));
  PIN_MutexUnlock(&entries_lock);
}

void instrumentINS(RTN& rtn)
{
  for (INS ins = RTN_InsHead(rtn); INS_Valid(ins); ins = INS_Next(ins)) {
    if (INS_IsStackRead(ins) || INS_IsStackWrite(ins)) {
      continue;
    }	
    if (INS_IsMemoryRead(ins)) {
      INS_InsertPredicatedCall(ins, IPOINT_BEFORE,
			       (AFUNPTR) read_ins,
			       IARG_THREAD_ID,
			       IARG_MEMORYREAD_EA,
			       IARG_INST_PTR,
			       IARG_END);
    }
    if (INS_HasMemoryRead2(ins)) {
      INS_InsertPredicatedCall(ins, IPOINT_BEFORE,
			       (AFUNPTR) read_ins,
			       IARG_THREAD_ID,
			       IARG_MEMORYREAD2_EA,
			       IARG_INST_PTR,
			       IARG_END);
    }
    if (INS_IsMemoryWrite(ins)) {
      INS_InsertPredicatedCall(ins, IPOINT_BEFORE,
			       (AFUNPTR) write_ins,
			       IARG_THREAD_ID,
			       IARG_MEMORYWRITE_EA,
			       IARG_INST_PTR,
			       IARG_END);
    }
  }
}

  
static VOID Image(IMG img, VOID * v) {
  if (!IMG_IsMainExecutable(img)) {
    return;
  }

  if (!tracefunctionlist.empty()) {
    for (vector<string>::const_iterator itr = tracefunctionlist.begin();
	 itr != tracefunctionlist.end();
	 ++itr) {
      RTN rtn = RTN_FindByName(img, (*itr).c_str());
      cerr << "DEBUG: tracing " << *itr << endl;
      if (!RTN_Valid(rtn)) {
	continue;
      }
      RTN_Open(rtn);
      instrumentINS(rtn);
      RTN_Close(rtn);
    }
    return;
  }
  
  for (SEC sec = IMG_SecHead(img); SEC_Valid(sec); sec = SEC_Next(sec)) {
    for (RTN rtn = SEC_RtnHead(sec); RTN_Valid(rtn); rtn = RTN_Next(rtn)) {
      RTN_Open(rtn);
      instrumentINS(rtn);
      RTN_Close(rtn);
    }
  }
}

void Fini(INT32 code, VOID *v)
{

  for (entriest::const_iterator eitr = entries.begin();
       eitr != entries.end();
       ++eitr) {
    cout << eitr->first << " "
	 << (eitr->second).tid << " "
      	 << (eitr->second).op << " "
      	 << (eitr->second).addr << endl;
  }

  cout << END << " " << END << " " << END << " " << END << endl;
}

int main(int argc, char *argv[])
{
  PIN_InitSymbols();
  if (PIN_Init(argc, argv)) {
    return 1;
  }

  string tmpfunclist = KnobTraceFunctionList.Value();
  if (tmpfunclist != "*") {
    std::istringstream ss(tmpfunclist);
    string token;
    while (std::getline(ss, token, ',')) {
      tracefunctionlist.push_back(token);
    }
  }

  PIN_MutexInit(&entries_lock);
    
  IMG_AddInstrumentFunction(Image, 0);

  PIN_AddFiniFunction(Fini, 0);

  PIN_StartProgram();

  //  cout << "yes" << endl;
  return 0;
}

