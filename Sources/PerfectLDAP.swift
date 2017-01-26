//
//  PerfectLDAP.swift
//  PerfectLDAP
//
//  Created by Rocky Wei on 2017-01-17.
//	Copyright (C) 2017 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2017 - 2018 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

/// C library of SASL
import SASL

/// C library of OpenLDAP
import OpenLDAP

/// Threading Library
import PerfectThread

/// Iconv
import PerfectICONV

/// CArray Helper
import PerfectCArray

/// Perfect LDAP Module
public class LDAP {

  /// Searching Scope
  public enum Scope : ber_int_t {
    case BASE = 0, SINGLE_LEVEL = 1, SUBTREE = 2, CHILDREN = 3, DEFAULT = -1
  }//end

  /// Authentication Model
  public enum AuthType {
    /// username@domain & password
    case SIMPLE
    /// GSS-API
    case GSSAPI
    /// GSS-SPNEGO
    case SPNEGO
    /// DIGEST MD5
    case DIGEST
  }//end 

  /// Error Handling
  public enum Exception: Error {
    /// Error with Message
    case message(String)
  }//end enum

  /// Explain the error code, typical usage is `throw Exception.message(LDAP.error(error_number))`
  /// - parameters:
  ///   - errno: Int32, the error number return by most ldap_XXX functions
  /// - returns:
  ///   a short text of explaination in English. *NOTE* string pointer of err2string is static so don't free it
  @discardableResult
  public static func error(_ errno: Int32) -> String {
    return String(cString: ldap_err2string(errno))
  }//end error

  /// time out value in terms of querying process, in seconds
  public var timeout: Int {
    get {
      var t = timeval(tv_sec: 0, tv_usec: 0)
      let _ = ldap_get_option(ldap, LDAP_OPT_TIMEOUT, &t)
      return t.tv_sec
    }//end get
    set {
      var t = timeval(tv_sec: timeout, tv_usec: 0)
      let _ = ldap_set_option(ldap, LDAP_OPT_TIMEOUT, &t)
    }//end set
  }//end timetout

  /// Searching result memory size limitations, for example, 1000 for 1000 lines?
  public var limitation: Int {
    get {
      var limit = 0
      let _ = ldap_get_option(ldap, LDAP_OPT_SIZELIMIT, &limit)
      return limit
    }//end get
    set {
      var limit = limitation
      let _ = ldap_set_option(ldap, LDAP_OPT_TIMEOUT, &limit)
    }//end set
  }//end limitation

  /// LDAP handler pointer
  internal var ldap: OpaquePointer? = nil
  
  /// codepage convertor
  internal var iconv: Iconv? = nil

  /// codepage reversely convertor
  internal var iconvR: Iconv? = nil

  /// convert string if encoding is required
  /// - parameters:
  ///   - ber: struct berval of the original buffer
  /// - returns:
  ///   encoded string
  public func string(ber: berval) -> String {
    guard let i = iconv else {
      return String(validatingUTF8: ber.bv_val) ?? ""
    }//end i
    return i.convert(from: ber)
  }//end string

  /// convert string if encoding is required
  /// - parameters:
  ///   - pstr: pointer of the original buffer, will apply null-terminated method
  /// - returns:
  ///   encoded string
  public func string(pstr: UnsafeMutablePointer<Int8>) -> String {
    let ber = berval(bv_len: strlen(pstr), bv_val: pstr)
    return self.string(ber: ber)
  }//end ber

  /// convert string to encoded binary data reversely
  /// *NOTE* MUST BE FREE MANUALLY
  /// - parameters:
  ///   - str: source utf8 string
  /// - returns:
  ///   encoded berval structure
  public func string(str: String) -> berval {
    guard let i = iconvR else {
      return str.withCString { ptr -> berval in
        return berval(bv_len: ber_len_t(str.utf8.count), bv_val: strdup(ptr))
      }//end str
    }//end str
    return str.withCString { ptr -> berval in
      let (p, sz) = i.convert(buf: ptr, length: str.utf8.count)
      return berval(bv_len: ber_len_t(sz), bv_val: p)
    }//end str
  }//end string

  private var _supportedControl = [String]()
  private var _supportedExtension = [String]()
  private var _supportedSASLMechanisms = [String]()
  private var _saslMech: [AuthType:String] = [:]

  public var supportedControl: [String] { get { return _supportedControl } }
  public var supportedExtension: [String] { get { return _supportedExtension } }
  public var supportedSASLMechanisms: [String] { get { return _supportedSASLMechanisms } }
  public var supportedSASL: [AuthType:String] { get { return _saslMech } }

  public func withUnsafeSASLDefaultsPointer<R>(mech: String = "", realm: String = "", authcid: String = "", passwd: String = "", authzid: String = "",_ body: (UnsafeMutableRawPointer?) throws -> R) rethrows -> R {
    var def = lutilSASLdefaults(mech: nil, realm: nil, authcid: nil, passwd: nil, authzid: nil, resps: nil, nresps: 0)
    if mech.isEmpty {
      let _ = ldap_get_option(self.ldap, LDAP_OPT_X_SASL_MECH, &(def.mech))
    } else {
      def.mech = ber_strdup(mech)
    }//end if
    if realm.isEmpty {
      let _ = ldap_get_option(self.ldap, LDAP_OPT_X_SASL_REALM, &(def.realm))
    } else {
      def.realm = ber_strdup(realm)
    }//end if
    if authcid.isEmpty {
      let _ = ldap_get_option(self.ldap, LDAP_OPT_X_SASL_AUTHCID, &(def.authcid))
    } else {
      def.authcid = ber_strdup(authcid)
    }//end if
    if authzid.isEmpty {
      let _ = ldap_get_option(self.ldap, LDAP_OPT_X_SASL_AUTHZID, &(def.authzid))
    } else {
      def.authzid = ber_strdup(authzid)
    }//end if
    if !passwd.isEmpty {
      def.passwd = ber_strdup(passwd)
    }//end if

    let r = try body(UnsafeMutablePointer(mutating: &def))

    if def.mech != nil {
      ber_memfree(def.mech)
    }//end if
    if def.realm != nil {
      ber_memfree(def.realm)
    }//end if
    if def.authcid != nil {
      ber_memfree(def.authcid)
    }//end if
    if def.authzid != nil {
      ber_memfree(def.authzid)
    }//end if
    if def.passwd != nil {
      ber_memfree(def.passwd)
    }//end if

    return r
  }

  /// constructor of LDAP. could be a simple LDAP() to local server or LDAP(url) with / without logon options.
  /// if login parameters were input, the process would block until finished.
  /// so it is strongly recommanded that call LDAP() without login option and call ldap.login() {} in async mode
  /// - parameters:
  ///   - url: String, something like ldap://somedomain.com:port
  ///   - username: String, user name to login, optional.
  ///   - password: String, password for login, optional.
  ///   - auth: AuthType, such as SIMPLE, GSSAPI, SPNEGO or DIGEST MD5
  ///   - codePage: object server coding page, e.g., GB2312, BIG5 or JS
  /// - throws:
  ///   possible exceptions of initial failed or access denied
  public init(url:String = "ldap://localhost", username: String? = nil, password: String? = nil, realm: String? = nil, auth: AuthType = .SIMPLE, codePage: Iconv.CodePage = .UTF8) throws {

    if codePage != .UTF8 {
      // we need a pair of code pages to transit in both directions.
      iconv = try Iconv(from: codePage, to: .UTF8)
      iconvR = try Iconv(from: .UTF8, to: codePage)
    }//end if

    ldap = OpaquePointer(bitPattern: 0)
    let r = ldap_initialize(&ldap, url)
    guard r == 0 else {
      throw Exception.message(LDAP.error(r))
    }//end guard

    guard let dse = try search() else {
      throw Exception.message("ROOT DSE FAULT")
    }//end dse

    guard let root = dse.dictionary[""] else {
      throw Exception.message("ROOT DSE HAS NO EXPECTED KEY")
    }//end root

    _supportedControl = root["supportedControl"] as? [String] ?? []
    _supportedExtension = root["supportedExtension"] as? [String] ?? []
    _supportedSASLMechanisms = root["supportedSASLMechanisms"] as? [String] ?? []

    _supportedSASLMechanisms.forEach { mech in
      if strstr(mech, "GSSAPI") != nil {
        _saslMech[AuthType.GSSAPI] = mech
      }else if strstr(mech, "GSS-SPNEGO") != nil {
        _saslMech[AuthType.SPNEGO] = mech
      }//end if
    }//next

    // if no login required, skip.
    if username == nil || password == nil {
      return
    }//end if

    // call login internally
    try login(username: username ?? "", password: password ?? "", realm: realm ?? "", auth: auth)
  }//end init



  /// login in synchronized mode, will block the calling thread
  /// - parameters:
  ///   - username: String, user name to login, optional.
  ///   - password: String, password for login, optional.
  ///   - auth: AuthType, such as SIMPLE, GSSAPI, SPNEGO or DIGEST MD5
  /// - returns:
  ///   true for a successful login.
  @discardableResult
  public func login(username: String, password: String, realm: String = "", auth: AuthType = .SIMPLE) throws {
    var r = Int32(0)
    let ex = Exception.message("UNSUPPORTED SECURITY MECH")
    switch auth {
    case .SIMPLE:
      var cred = berval(bv_len: ber_len_t(password.utf8.count), bv_val: ber_strdup(password))
      r = ldap_sasl_bind_s(self.ldap, username, nil, &cred, nil, nil, nil)
      ber_memfree(cred.bv_val)
    case .GSSAPI, .SPNEGO:
      guard let mech = _saslMech[auth] else {
        throw ex
      }//end
      r = self.withUnsafeSASLDefaultsPointer(mech: mech, realm: realm, authcid: username, passwd: password) { ldap_sasl_interactive_bind_s(ldap, username, _saslMech[.GSSAPI], nil, nil, LDAP_SASL_AUTOMATIC, { ldapHandle, flags, defaults, input in

        guard flags != LDAP_SASL_QUIET else {
          return LDAP_OTHER
        }//END GUARD

        let defaultsPointer = unsafeBitCast(defaults, to: UnsafeMutablePointer<lutilSASLdefaults>.self)
        let def = defaultsPointer.pointee

        guard let pInput = input else {
          return -1
        }//end guard

        var cursor: UnsafeMutablePointer<sasl_interact_t> = unsafeBitCast(pInput, to: UnsafeMutablePointer<sasl_interact_t>.self)

        var interact = cursor.pointee

        while(Int32(interact.id) != SASL_CB_LIST_END) {

          switch(Int32(interact.id)) {
          case SASL_CB_GETREALM:
            SASLReply(pInteract: cursor, pDefaults: defaultsPointer, pMsg: def.realm)
          case SASL_CB_AUTHNAME:
            SASLReply(pInteract: cursor, pDefaults: defaultsPointer, pMsg: def.authcid)
          case SASL_CB_PASS:
            SASLReply(pInteract: cursor, pDefaults: defaultsPointer, pMsg: def.passwd)
          case SASL_CB_USER:
            SASLReply(pInteract: cursor, pDefaults: defaultsPointer, pMsg: def.authzid)
          case SASL_CB_NOECHOPROMPT, SASL_CB_ECHOPROMPT: // skipped
            ()
          default: //unknown
            return -1
          }//end case
          cursor.pointee = interact
          cursor = cursor.successor()
          interact = cursor.pointee
        }//end while

        return Int32(0)}, $0) }
    default:
      throw ex
    }
    if r == 0 {
      return
    }else {
      throw Exception.message(LDAP.error(r))
    }//end
  }//end login

  /// Login in asynchronized mode. Once completed, it would invoke the callback handler
  /// - parameters:
  ///   - username: String, user name to login, optional.
  ///   - password: String, password for login, optional.
  ///   - auth: AuthType, such as SIMPLE, GSSAPI, SPNEGO or DIGEST MD5
  ///   - completion: callback handler with a boolean parameter indicating whether login succeeded or not.
  public func login(username: String, password: String, realm: String = "", auth: AuthType = .SIMPLE, completion: @escaping (String?)->Void) {
    Threading.dispatch {
      do {
        try self.login(username: username, password: password, realm: realm, auth: auth)
        completion(nil)
      }catch(let err) {
        completion("LOGIN FAILED: \(err)")
      }
    }//end thread
  }//end login

  /// destructor of the class
  deinit {
    ldap_unbind_ext_s(ldap, nil, nil)
  }//end deinit


  /// Attribute of a searching result
  public struct Attribute {

    /// name of the attribute
    internal var _name = ""

    /// name of the attribute, read only
    public var name: String { get { return _name } }

    /// value set of the attribute, as an array of string
    internal var _values = [String]()

    /// value set of the attribute, as an array of string, read only
    public var values:[String] { get { return _values } }

    /// constructor of Attribute
    /// - parameters:
    ///   - ldap: the LDAP handler
    ///   - entry: the LDAPMessage (single element)
    ///   - tag: attribute name returned by ldap_xxx_attribute
    public init (ldap: LDAP, entry:OpaquePointer, tag:UnsafePointer<Int8>) {
      _name = String(cString: tag)
      let valueSet = ldap_get_values_len(ldap.ldap, entry, tag)
      var cursor = valueSet
      while(cursor != nil) {
        guard let pBer = cursor?.pointee else {
          break
        }//end guard
        let b = pBer.pointee
        _values.append(ldap.string(ber: b))
        cursor = cursor?.successor()
      }//end cursor
      if valueSet != nil {
        ldap_value_free_len(valueSet)
      }//end if
    }//end init
  }//end Attribute

  /// Attributes Set of a Searching result
  public struct AttributeSet {

    /// name of the attribute
    internal var _name = ""

    /// name of the attribute, read only
    public var name: String { get { return _name } }

    /// attribute value set array
    internal var _attributes = [Attribute]()

    /// attribute value set array, read only
    public var attributes: [Attribute] { get { return _attributes } }

    /// constructor of Attribute
    /// - parameters:
    ///   - ldap: the LDAP handler
    ///   - entry: the LDAPMessage (single element)
    public init (ldap: LDAP, entry:OpaquePointer) {
      guard let pName = ldap_get_dn(ldap.ldap, entry) else {
        return
      }//end pName
      _name = ldap.string(pstr: pName)
      ldap_memfree(pName)
      var ber = OpaquePointer(bitPattern: 0)
      var a = ldap_first_attribute(ldap.ldap, entry, &ber)
      while(a != nil) {
        _attributes.append(Attribute(ldap: ldap, entry: entry, tag: a!))
        ldap_memfree(a)
        a = ldap_next_attribute(ldap.ldap, entry, ber)
      }//end while
      ber_free(ber, 0)
    }//end init
  }//end class

  /// a reference record of an LDAP search result
  public struct Reference {

    /// value set in an array of string
    internal var _values = [String] ()

    /// value set in an array of string, read only
    public var values: [String] { get { return _values } }

    /// constructor of Reference
    /// - parameters:
    ///   - ldap: the LDAP handler
    ///   - reference: the LDAPMessage (single element)
    public init(ldap:LDAP, reference:OpaquePointer) {
      var referrals = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>(bitPattern: 0)

      // *NOTE* ldap_value_free is deprecated so have to use memfree in chain instead
      let r = ldap_parse_reference(ldap.ldap, reference, &referrals, nil, 0)
      guard r == 0 else {
        return
      }//end guard
      var cursor = referrals
      while(cursor != nil) {
        guard let pstr = cursor?.pointee else {
          break
        }//end guard
        _values.append(ldap.string(pstr: pstr))
        ldap_memfree(pstr)
        cursor = cursor?.successor()
      }//end while
      ldap_memfree(referrals)
    }//end init
  }//end struct

  /// LDAP Result record
  public struct Result {

    /// error code of result
    internal var _errCode = Int32(0)

    /// error code of result, read only
    public var errCode: Int { get { return Int(_errCode) } }

    /// error message
    internal var _errMsg = ""

    /// error message, read only
    public var errMsg: String { get { return _errMsg } }

    /// matched dn
    internal var _matched = ""

    /// matched dn, read only
    public var matched: String { get { return _matched } }

    /// referrals as an array of string
    internal var _ref = [String]()

    /// referrals as an array of string, read only
    public var referrals: [String] { get { return _ref } }
    
    /// constructor of Result
    /// - parameters:
    ///   - ldap: the LDAP handler
    ///   - result: the LDAPMessage (single element)
    public init(ldap:LDAP, result:OpaquePointer) {
      var emsg = UnsafeMutablePointer<Int8>(bitPattern: 0)
      var msg = UnsafeMutablePointer<Int8>(bitPattern: 0)
      var ref = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>(bitPattern: 0)
      let r = ldap_parse_result(ldap.ldap, result, &_errCode, &msg, &emsg, &ref, nil, 0)
      guard r == 0 else {
        return
      }//end guard
      if msg != nil {
        _matched = ldap.string(pstr: msg!)
        ldap_memfree(msg)
      }//end if
      if emsg != nil {
        _errMsg = ldap.string(pstr: emsg!)
        ldap_memfree(emsg)
      }//end if
      var rf = ref
      while(rf != nil) {
        guard let p = rf?.pointee else {
          break
        }
        _ref.append(ldap.string(pstr: p))
        ldap_memfree(p)
        rf = rf?.successor()
      }//end rf
      if ref != nil {
        ldap_memfree(ref)
      }//end if
    }//end Result
  }
  /// Result set of a searching query
  public struct ResultSet {

    /// attribute set as an array
    internal var _attr = [AttributeSet]()

    /// attribute set as an array, read only
    public var attributeSet: [AttributeSet] { get { return _attr } }

    /// as an dictionary, read only
    public var dictionary:[String:[String:Any]] { get {
      var dic:[String:[String:Any]] = [:]
      for aset in _attr {
        var d: [String: Any] = [:]
        for a in aset.attributes {
          if a.values.count > 1 {
            d[a.name] = a.values
          }else {
            d[a.name] = a.values[0]
          }//end if
        }//next a
        dic[aset.name] = d
      }//next aset
      return dic
    } } //end simple

    /// references as an array
    internal var _ref = [Reference]()

    /// references as an array, read only
    public var references: [Reference] { get { return _ref } }

    /// results as an array of result
    internal var _results = [Result]()

    /// results as an array of result, read only
    public var result: [Result] { get { return _results } }

    /// constructor of Attribute
    /// - parameters:
    ///   - ldap: the LDAP handler
    ///   - chain: the LDAPMessage chain elements
    public init (ldap: LDAP, chain:OpaquePointer) {
      var m = ldap_first_message(ldap.ldap, chain)
      while(m != nil) {
        switch(UInt(ldap_msgtype(m))) {
        case LDAP_RES_SEARCH_ENTRY:
          _attr.append(AttributeSet(ldap: ldap, entry: m!))
        case LDAP_RES_SEARCH_REFERENCE:
          _ref.append(Reference(ldap: ldap, reference: m!))
        case LDAP_RES_SEARCH_RESULT:
          _results.append(Result(ldap: ldap, result: m!))
        default:
          ()
        }//end case
        m = ldap_next_message(ldap.ldap, m)
      }//end while
    }//end init
  }//end struct

  /// constant to indicate a sorting order: ascendant or descendant.
  public enum SortingOrder {
    case ASC
    case DSC
  }//end SortingOrder

  /// generate a standard sorting string from a series of fields
  /// - parameters:
  ///   - sortedBy: an array of tuple, which tells each field to sort in what order
  /// - returns:
  ///   the sorting language, as a string
  @discardableResult
  public static func sortingString( sortedBy: [(String, SortingOrder)] = [] ) -> String {
    return sortedBy.reduce("") { previous, next in
      let str = next.1 == .ASC ? next.0 : "-" + next.0
      return previous.isEmpty ? str : previous + " " + str
    }//end reduce
  }//end sortingString

  /// synchronized search
  /// - parameters: 
  ///   - base: String, search base domain (dn), default = ""
  ///   - filter: String, the filter of query, default = "(objectclass=*)", means all possible results
  ///   - scope: See Scope, BASE, SINGLE_LEVEL, SUBTREE or CHILDREN
  ///   - sortedBy: a sorting string, may be generated by LDAP.sortingString()
  /// - returns:
  ///   ResultSet. See ResultSet
  /// - throws:
  ///   Exception.message
  @discardableResult
  public func search(base:String = "", filter:String = "(objectclass=*)", scope:Scope = .BASE, attributes: [String] = [], sortedBy: String = "") throws -> ResultSet? {

    var serverControl = UnsafeMutablePointer<LDAPControl>(bitPattern: 0)

    if !sortedBy.isEmpty {
      var sortKeyList = UnsafeMutablePointer<UnsafeMutablePointer<LDAPSortKey>?>(bitPattern: 0)
      let sortString = strdup(sortedBy)
      var r = ldap_create_sort_keylist(&sortKeyList, sortString)
      free(sortString)
      if r != 0 {
        throw Exception.message(LDAP.error(r))
      }//end if

      r = ldap_create_sort_control(self.ldap, sortKeyList, 0, &serverControl)
      ldap_free_sort_keylist(sortKeyList)
      if r != 0 {
        throw Exception.message(LDAP.error(r))
      }//end if
    }//end if

    // prepare the return set
    var msg = OpaquePointer(bitPattern: 0)

    let r = withCArrayOfString(array: attributes) { pAttribute -> Int32 in

      // perform the search
      let result = ldap_search_ext_s(self.ldap, base, scope.rawValue, filter, pAttribute, 0, &serverControl, nil, nil, 0, &msg)

      if serverControl != nil {
        ldap_control_free(serverControl)
      }
      return result
    }//end

    // validate the query
    guard r == 0 && msg != nil else {
      throw Exception.message(LDAP.error(r))
    }//next

    // process the result set
    let rs = ResultSet(ldap: self, chain: msg!)

    // release the memory
    ldap_msgfree(msg)

    return rs
  }//end search

  /// asynchronized search
  /// - parameters:
  ///   - base: String, search base domain (dn), default = ""
  ///   - filter: String, the filter of query, default = "(objectclass=*)", means all possible results
  ///   - scope: See Scope, BASE, SINGLE_LEVEL, SUBTREE or CHILDREN
  ///   - sortedBy: a sorting string, may be generated by LDAP.sortingString()
  ///   - completion: callback with a parameter of ResultSet, nil if failed
  @discardableResult
  public func search(base:String = "", filter:String = "(objectclass=*)", scope:Scope = .BASE, sortedBy: String = "", completion: @escaping (ResultSet?)-> Void) {
    Threading.dispatch {
      var rs: ResultSet? = nil
      do {
        rs = try self.search(base: base, filter: filter, scope: scope, sortedBy: sortedBy)
      }catch {
        rs = nil
      }//end catch
      completion(rs)
    }//end threading
  }//end search

  /// allocate a modification structure for internal usage
  /// - parameters:
  ///   - method: method of modification, i.e., LDAP_MOD_ADD or LDAP_MOD_REPLACE or LDAP_MOD_DELETE and LDAP_MOD_BVALUES
  ///   - key: attribute name to modify
  ///   - values: attribute values as an array
  /// - returns:
  ///   an LDAPMod structure
  @discardableResult
  internal func modAlloc(method: Int32, key: String, values: [String]) -> LDAPMod {
    let pValues = values.map { self.string(str: $0) }
    let pointers = pValues.asUnsafeNullTerminatedPointers()
    return LDAPMod(mod_op: method, mod_type: strdup(key), mod_vals: mod_vals_u(modv_bvals: pointers))
  }//end modAlloc

  /// add an attribute to a DN
  /// - parameters:
  ///   - distinguishedName: specific DN
  ///   - attributes: attributes as an dictionary to add
  /// - throws:
  ///   - Exception with message, such as no permission, or object class violation, etc.
  @discardableResult
  public func add(distinguishedName: String, attributes: [String:[String]]) throws {

    // map the keys to an array
    let keys:[String] = attributes.keys.map { $0 }

    // map the key array to a modification array
    let mods:[LDAPMod] = keys.map { self.modAlloc(method: LDAP_MOD_ADD | LDAP_MOD_BVALUES, key: $0, values: attributes[$0]!)}

    // get the pointers
    let pMods = mods.asUnsafeNullTerminatedPointers()

    // perform adding
    let r = ldap_add_ext_s(self.ldap, distinguishedName, pMods, nil, nil)

    // release memory
    ldap_mods_free(pMods, 0)

    if r == 0 {
      return
    }//end if

    throw Exception.message(LDAP.error(r))
  }//end func

  /// add an attribute to a DN
  /// - parameters:
  ///   - distinguishedName: specific DN
  ///   - attributes: attributes as an dictionary to add
  ///   - completion: callback once done. If something wrong, an error message will pass to the closure.
  @discardableResult
  public func add(distinguishedName: String, attributes: [String:[String]],completion: @escaping (String?)-> Void) {

    Threading.dispatch {
      do {
        // perform adding
        try self.add(distinguishedName: distinguishedName, attributes: attributes)

        // if nothing wrong, callback
        completion(nil)

      }catch(let err) {

        // otherwise callback an error
        completion("\(err)")
      }//end do

    }//end dispatch
  }//end func

  /// modify an attribute to a DN
  /// - parameters:
  ///   - distinguishedName: specific DN
  ///   - attributes: attributes as an dictionary to modify
  /// - throws:
  ///   - Exception with message, such as no permission, or object class violation, etc.
  @discardableResult
  public func modify(distinguishedName: String, attributes: [String:[String]]) throws {

    // map the keys to an array
    let keys:[String] = attributes.keys.map { $0 }

    // map the key array to a modification array
    let mods:[LDAPMod] = keys.map { self.modAlloc(method: LDAP_MOD_REPLACE | LDAP_MOD_BVALUES, key: $0, values: attributes[$0]!)}

    // get the pointers
    let pMods = mods.asUnsafeNullTerminatedPointers()

    // perform modification
    let r = ldap_modify_ext_s(self.ldap, distinguishedName, pMods, nil, nil)

    // release memory
    ldap_mods_free(pMods, 0)

    if r == 0 {
      return
    }//end if

    throw Exception.message(LDAP.error(r))
  }//end func

  /// modify an attribute to a DN
  /// - parameters:
  ///   - distinguishedName: specific DN
  ///   - attributes: attributes as an dictionary to modify
  ///   - completion: callback once done. If something wrong, an error message will pass to the closure.
  @discardableResult
  public func modify(distinguishedName: String, attributes: [String:[String]],completion: @escaping (String?)-> Void) {
    Threading.dispatch {
      do {
        // perform adding
        try self.modify(distinguishedName: distinguishedName, attributes: attributes)

        // if nothing wrong, callback
        completion(nil)

      }catch(let err) {

        // otherwise callback an error
        completion("\(err)")
      }//end do
      
    }//end dispatch
  }//end func

  /// delete an attribute to a DN
  /// - parameters:
  ///   - distinguishedName: specific DN
  ///   - attributes: attributes as an dictionary to delete
  /// - throws:
  ///   - Exception with message, such as no permission, or object class violation, etc.
  @discardableResult
  public func delete(distinguishedName: String) throws {

    // perform deletion
    let r = ldap_delete_ext_s(self.ldap, distinguishedName, nil, nil)

    if r == 0 {
      return
    }//end if

    throw Exception.message(LDAP.error(r))
  }

  /// delete an attribute to a DN
  /// - parameters:
  ///   - distinguishedName: specific DN
  ///   - attributes: attributes as an dictionary to delete
  ///   - completion: callback once done. If something wrong, an error message will pass to the closure.
  @discardableResult
  public func delete(distinguishedName: String, completion: @escaping (String?)-> Void) {
    Threading.dispatch {
      do {
        // perform adding
        try self.delete(distinguishedName: distinguishedName)

        // if nothing wrong, callback
        completion(nil)

      }catch(let err) {

        // otherwise callback an error
        completion("\(err)")
      }//end do

    }//end dispatch
  }
}//end class
















