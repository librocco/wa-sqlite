// Copyright 2024 Roy T. Hashimoto. All Rights Reserved.
// This file should be included in the build with --post-js.

(function() {
  const AsyncFunction = Object.getPrototypeOf(async function() { }).constructor;

  // This list of methods must match exactly with libfunction.c.
  const FUNC_METHODS = [
    'xFunc',
    'xStep',
    'xFinal'
  ];

  const mapFunctionNameToKey = new Map();

  Module['create_function'] = function(db, zFunctionName, nArg, eTextRep, pApp, xFunc, xStep, xFinal) {
    // Allocate some memory to store the async flags. In addition, this
    // pointer is passed to SQLite as the application data (the user's
    // application data is ignored), and is used to look up the JavaScript
    // target object.
    const pAsyncFlags = Module['_sqlite3_malloc'](4);
    const target = { xFunc, xStep, xFinal };

    setValue(pAsyncFlags, FUNC_METHODS.reduce((mask, method, i) => {
      if (target[method] instanceof AsyncFunction) {
        return mask | 1 << i;
      }
      return mask;
    }, 0), 'i32');

    const result = ccall(
      'libfunction_create_function',
      'number',
      ['number', 'string', 'number', 'number', 'number', 'number', 'number', 'number'],
      [
        db,
        zFunctionName,
        nArg,
        eTextRep,
        pAsyncFlags,
        xFunc ? 1 : 0,
        xStep ? 1 : 0,
        xFinal ? 1 : 0
      ]);
    if (!result) {
      if (mapFunctionNameToKey.has(zFunctionName)) {
        // Reclaim the old resources used with this name.
        const oldKey = mapFunctionNameToKey.get(zFunctionName);
        Module['deleteCallback'](oldKey);
      }
      mapFunctionNameToKey.set(zFunctionName, pAsyncFlags);
      Module['setCallback'](pAsyncFlags, { xFunc, xStep, xFinal });
    }
    return result;
  };

  /**
   * Adapts the update hook callback to serve as a bridge between the C-side callback and the JS callback:
   * - str pointer -> string 
   * - legalized i64 (lo32, hi32) -> bigint
   *
   * @param {(updateType: 9 | 18 | 23, dbName: string, tblName: string, rowid: bigint) => void} f
   * @returns {(updateType: number, dbName: number, tblName: number, lo32: number, hi32: number) => void}
   */
  const adaptHookCb = (f) => (ut, dbn, tbn, lo32, hi32) => {
    const rowid = delegalize(lo32, hi32);
    const dbName = Module.UTF8ToString(dbn)
    const tblName = Module.UTF8ToString(tbn)
    f(ut, dbName, tblName, rowid)
  }

  Module['updateHook'] = function(db, f) {
    const key = Math.floor(Math.random() * 10000)
    Module["setCallback"](key, adaptHookCb(f))

    return ccall(
      'libfunction_update_hook',
      'void',
      ['number', 'number'],
      [db, key]
    );
  }
})();

// Emscripten "legalizes" 64-bit integer arguments by passing them as
// two 32-bit signed integers.
function delegalize(lo32, hi32) {
  return (BigInt(hi32) << 32n) | (BigInt(lo32) & 0xffffffffn);
}
