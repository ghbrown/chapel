use IO;
const filename = "foo";

/////////////////////////////////////////////////////////////////////////////
// a simplified example

record MyRecord {
  var de: unmanaged RootClass;
// this works: var de = new unmanaged RootClass();
}

class MyClass {
  var files = new map(string, MyRecord);
}

const myC = new unmanaged MyClass();

// TODO: The following seems to create an extra new unmanaged RootClass()
// that is not deleted by `myC.files[filename].de` below.
// Once this test passes memleaks testing, remove the --memLeaks .execopts.
myC.files[filename] = new MyRecord(new unmanaged RootClass());

writeln(myC);  // {files = {foo: (de = {})}}

delete myC.files[filename].de;
delete myC;

/////////////////////////////////////////////////////////////////////////////
// the original recursive case by @cassella

record recordthatcontainsadirent {
  var de: unmanaged dirent;
}

class dirent {
  var files = new map(string, recordthatcontainsadirent);
}

var curdir = new unmanaged dirent();

curdir.files[filename] = new recordthatcontainsadirent(new unmanaged dirent());

writeln(curdir);  // {files = {foo: (de = {files = {}})}}

delete curdir.files[filename].de;
delete curdir;

use ChapelHashtable;
// To preserve this future behavior after map updates,
// a snapshot of `map` was taken at the time of this future
// creation
record map {
  type keyType;
  type valType;

  param parSafe = false;

  const resizeThreshold = defaultHashTableResizeThreshold;

  var table: chpl__hashtable(keyType, valType);

  proc init(type keyType, type valType,
            resizeThreshold=defaultHashTableResizeThreshold,
            initialCapacity=16) {
    this.keyType = keyType;
    this.valType = valType;
    this.parSafe = false;
    if resizeThreshold <= 0 || resizeThreshold >= 1 {
      warning("'resizeThreshold' must be between 0 and 1.",
              " 'resizeThreshold' will be set to 0.5");
      this.resizeThreshold = 0.5;
    } else {
      this.resizeThreshold = resizeThreshold;
    }
    table = new chpl__hashtable(keyType, valType, this.resizeThreshold,
                                initialCapacity);
  }

  proc ref this(k: keyType) ref throws
    where isDefaultInitializable(valType) {
    var (_, slot) = table.findAvailableSlot(k);
    if !table.isSlotFull(slot) {
      var val: valType;
      table.fillSlot(slot, k, val);
    }
    return table.table[slot].val;
  }

  proc const this(k: keyType) const throws
  where shouldReturnRvalueByValue(valType) &&
       !isNonNilableClass(valType) {
    var (found, slot) = table.findFullSlot(k);
    if !found then
      throw new KeyNotFoundError(k:string);
    const result = table.table[slot].val;
    return result;
  }

  proc const this(k: keyType) const ref throws
  where !isNonNilableClass(valType) {
    var (found, slot) = table.findFullSlot(k);
    if !found then
      throw new KeyNotFoundError(k:string);
    const ref result = table.table[slot].val;
    return result;
  }

  proc const this(k: keyType) throws
  where isNonNilableClass(valType) {
    var (found, slot) = table.findFullSlot(k);
    if !found then
      throw new KeyNotFoundError(k:string);
    try! {
      var result = table.table[slot].val.borrow();
      if isNonNilableClass(valType) {
        return result!;
      } else {
        return result;
      }
    }
  }

  proc writeThis(fw: fileWriter) throws {
    var first = true;

    fw.writeLiteral("{");
    for slot in table.allSlots() {
      if table.isSlotFull(slot) {
        if first {
          first = false;
        } else {
          fw.writeLiteral(", ");
        }
        ref tabEntry = table.table[slot];
        ref key = tabEntry.key;
        ref val = tabEntry.val;
        fw.write(key);
        fw.writeLiteral(": ");
        fw.write(val);
      }
    }
    fw.writeLiteral("}");
  }

  class KeyNotFoundError : Error {
    proc init() {}

    proc init(k: string) {
      var msg = "key '" + k + "' not found";
      super.init(msg);
    }
  }
}
