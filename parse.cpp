#include <iostream>
#include <stdint.h>
#include <map>
#include <set>
#include "macros.h"
#include <assert.h>

using namespace std;

#include <fstream>

struct defsetcmp {
  bool operator() (const pair<uint64_t, uint64_t> &l, const pair<uint64_t, uint64_t> &r) {
    return (l.first < r.first || l.second < r.second);
  }
};

int main(int argc, char *argv[])
{
  if (argc != 2) {
    cerr << "Usage: ./parse file" << endl;
    return(1);
  }

  ifstream inFile(argv[1]);

  map<uint64_t, uint64_t> latestWrite;

  typedef  map<pair<uint64_t, uint64_t>, set<uint64_t>, defsetcmp> defsett;
  defsett defset;

  map<uint64_t, bool> localread;
  map<uint64_t, bool> nonlocalread;

  map<uint64_t, uint64_t> ins2tid;

  map<uint64_t, map<uint64_t, bool> > has_read;
  map<uint64_t, bool> follower;
  
  while (inFile.good()) {
    uint64_t ins, tid, rw, addr;
    inFile >> ins >> tid >> rw >> addr;
    if (ins == END && addr == END) {

      latestWrite.clear();

      ins2tid.clear();

      has_read.clear();

    } else if (rw == READ) {

      ins2tid[ins] = tid;

      //if there are no writes to current variable yet then continue
      if (latestWrite.find(addr) == latestWrite.end()) {
	continue;
      }

      uint64_t latestWriteIns = latestWrite[addr];

      //defset
      defset[make_pair(addr,ins)].insert(latestWriteIns);
      
      //local non-local
      bool isLocal = (tid == ins2tid[latestWriteIns]);
      if (localread.find(ins) == localread.end()) {
	localread[ins] = isLocal;
	nonlocalread[ins] = !isLocal;
      } else {
	localread[ins] = localread[ins] && isLocal;
	nonlocalread[ins] = nonlocalread[ins] && !isLocal;
      }

      //follower
      if (has_read.find(addr) != has_read.end()
	  && has_read[addr].find(tid) != has_read[addr].end()) {
	if (follower.find(ins) != follower.end()) {
	  follower[ins] = follower[ins] && has_read[addr][tid];
	} else {
	  follower[ins] = has_read[addr][tid];
	}
      }
      has_read[addr][tid] = true;

    } else {
      assert(rw == WRITE);

      ins2tid[ins] = tid;

      latestWrite[addr] = ins;

      if(has_read.find(addr) != has_read.end()) {
	for(map<uint64_t, bool>::iterator titr = has_read[addr].begin();
	    titr != has_read[addr].end();
	    ++titr) {
	  titr->second = false;
	}
      }
    }
  }      
      
  inFile.close();

  //print defset
  //variable read_ins_addr #writes write_ins_add0 ...
  for (defsett::const_iterator defsetitr = defset.begin();
       defsetitr != defset.end();
       ++defsetitr) {
    cout << defsetitr->first.first << " " << defsetitr->first.second << " ";
    cout << (defsetitr->second).size() << " ";
    for (set<uint64_t>::const_iterator witr = (defsetitr->second).begin();
	 witr != (defsetitr->second).end();
	 ++witr) {
      cout << *witr << " ";
    }
    cout << endl;
  }

  //print local and non local
  cout << "#local: " << endl;
  for(map<uint64_t, bool>::const_iterator litr = localread.begin();
      litr != localread.end();
      ++litr) {
    if (litr->second) {
      cout << litr->first << endl;
    }
  }
    cout << "#nonlocal: " << endl;
  for(map<uint64_t, bool>::const_iterator nlitr = nonlocalread.begin();
      nlitr != nonlocalread.end();
      ++nlitr) {
    if (nlitr->second) {
      cout << nlitr->first << endl;
    }
  }
  
  //print follower
    cout << "#follower: " << endl;
  for(map<uint64_t, bool>::const_iterator fitr = follower.begin();
      fitr != follower.end();
      ++fitr) {
    if (fitr->second) {
      cout << fitr->first << endl;
    }
  }
      
  return 0;
}

