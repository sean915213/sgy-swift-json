//
//  SGYJSONSerializer.swift
//  SGYSwiftJSON
//
//  Created by Sean Young on 9/25/15.
//  Copyright © 2015 Sean Young. All rights reserved.
//

/// A JSON serialization class.
public class SGYJSONSerializer {
    
    /**
     Errors thrown during serialization.
     
     - InvalidDictionaryKeyType(`Any.Type`): A dictionary key encountered could not be cast to `String` and does not implement the `CustomStringConvertible` protocol.
     - NSJSONSerializationError(`NSError`): An error occurred seralizing the resulting (supposedly safe) object graph.  This should probably be considered a bug.
     */
    public enum Error: ErrorType {
        /**
         Indicates a dictionary key encountered could not be cast to `String` and does not implement the `CustomStringConvertible` protocol.
         
         - returns: An `InvalidDictionaryKeyType` case initialized with the offending type.
         */
        case InvalidDictionaryKeyType(Any.Type),
        /**
        Indicates an error occurred seralizing the resulting (supposedly safe) object graph.  This should probably be considered a bug.
        
        - returns: An `NSJSONSerializationError` case initialized with the caught `NSError`.
        */
        NSJSONSerializationError(NSError)
    }

    // MARK: - Initialization
    
    /**
    Initializes a new instance.
    
    - returns: An `SGYJSONSerializer` instance.
    */
    public init() { }
    
    // MARK: - Properties
    
    /// Determines whether `InvalidDictionaryKeyType` errors are thrown.
    public var strictMode = true
    /// The writing options used during serialization.
    public var writingOptions = NSJSONWritingOptions()
    /// The block this instance will call in order to convert `NSDate` values to a valid JSON leaf value.
    public var dateConversionBlock: ((date: NSDate) -> JSONLeafValue?)?
    
    // MARK: - Methods
    // MARK: Public

    /**
    Attempts serializing all the elements within a collection implementing `SGYCollectionReflection`.
    
    - parameter collection: An object implementing `SGYCollectionReflection`.
    
    - throws: All `SGYJSONSerializer.Error` types.
    
    - returns: Serialized collection JSON as `NSData`.
    */
    public func serialize(collection: SGYCollectionReflection) throws -> NSData {
        let array = try convertToValidCollection(collection)
        return try serializeObject(array)
    }
    
    /**
     Attempts serializing all the elements within a dictionary implementing `SGYDictionaryReflection`.
     
     - parameter dictionary: An object implementing `SGYDictionaryReflection`.
     
     - throws: All `SGYJSONSerializer.Error` types.
     
     - returns: Serialized dictionary JSON as `NSData`.
     */
    public func serialize(dictionary: SGYDictionaryReflection) throws -> NSData {
        let dictionary = try convertToValidDictionary(dictionary)
        return try serializeObject(dictionary)
    }
    
    /**
     Attempts serializing an instance of `AnyObject`.
     
     - parameter object: An instance of `AnyObject`.
     
     - throws: All `SGYJSONSerializer.Error` types.
     
     - returns: Serialized object JSON as `NSData`.
     */
    public func serialize(object: Any) throws -> NSData {
        // Attempt converting object to dictionary
        let dictionary = try convertToValidDictionary(object)
        return try serializeObject(dictionary)
    }
    
    // MARK: Private
    
    private func serializeObject(object: AnyObject) throws -> NSData {
        do { return try NSJSONSerialization.dataWithJSONObject(object, options: writingOptions) }
        catch let e as NSError { throw Error.NSJSONSerializationError(e) }
    }
    
    private func convertToValidDictionary(object: Any) throws -> [String: AnyObject] {
        // Converted dictionary
        var jsonDictionary = [String: AnyObject]()
        
        var mirror: Mirror? = Mirror(reflecting: object)
        while mirror != nil {
            // Pull values from mirror children
            for child in mirror!.children {
                // Make sure property has a label (don't know when it doesn't, but it's defined optional)
                guard let property = child.label else { continue }
                // Attempt parsing value into valid type
                guard let validObject = try convertToValidObject(child.value) else { continue }
                // Assign to dictionary
                jsonDictionary[property] = validObject
            }
            // Assign super's mirror if any and loop back through
            mirror = mirror!.superclassMirror()
        }
        
        return jsonDictionary
    }
    
    private func convertToValidCollection(collection: SGYCollectionReflection) throws -> [AnyObject] {
        var validCollection = [AnyObject]()
        // Get child values
        for (_, value) in Mirror(reflecting: collection).children {
            if let validObj = try convertToValidObject(value) { validCollection.append(validObj) }
        }
        // Return collection even if empty. Caller determines what to do.
        return validCollection
    }
    
    private func convertToValidDictionary(dictionary: SGYDictionaryReflection) throws -> [String: AnyObject] {
        var validDict = [String: AnyObject]()
        // Get child key-value tuples
        for (_, kvp) in Mirror(reflecting: dictionary).children {
            let tuplePair = Mirror(reflecting: kvp).children.map { $0.value }
            // A string key is required so attempt deriving one
            var key: String? = tuplePair[0] as? String
            // If not immediately a string try CustomStringConvertible
            if let stringObj = tuplePair[0] as? CustomStringConvertible where key == nil { key = stringObj.description }
            // If still nil cannot continue
            guard let validKey = key else {
                // If in strict mode throw
                if strictMode { throw Error.InvalidDictionaryKeyType(tuplePair[0].dynamicType) }
                //. Otherwise simply skip
                continue
            }
            
            // Assign if we receive valid result
            if let validValue = try convertToValidObject(tuplePair[1]) { validDict[validKey] = validValue }
        }
        
        return validDict
    }
    
    
    private func convertToValidObject(any: Any) throws -> AnyObject? {
        // Any could be optional but is not recognized as being able to be cast as such.  So unwrap using the protocol.
        guard let object = unwrap(any) else { return nil }
        
        // Any object could implement JSONProxyProvider to provide an alternate representation so check this first.
        if let proxyProvider = object as? JSONProxyProvider {
            // This protocol only requires Any so recursively attempt conversion on proxy object
            return try convertToValidObject(proxyProvider.jsonProxy)
        }
        
        // Similarly any object may implement JSONLeafRepresentable so check this next
        if let leafObject = object as? JSONLeafRepresentable {
            return leafObject.jsonLeafValue?.value
        }
        
        // Date
        if let date = object as? NSDate {
            return dateConversionBlock?(date: date)?.value
        }
        
        // -- Array, Dictionary, or Complex

        // Dictionary
        // IMPORTANT: Check dictionary first since both Dictionary and Array adhere to SGYCollectionReflection due to the SequenceType extension.
        if let dictionary = object as? SGYDictionaryReflection {
            let validDict = try convertToValidDictionary(dictionary)
            // Skip empty dictionaries
            return validDict.isEmpty ? nil : validDict
        }
        
        // Collection
        if let collection = object as? SGYCollectionReflection {
            let array = try convertToValidCollection(collection)
            // Skip empty collections
            return array.isEmpty ? nil : array
        }
        
        // Complex object
        let objDict = try convertToValidDictionary(object)
        // Skip empty dictionaries
        return objDict.isEmpty ? nil : objDict
    }
    
    private func unwrap(any: Any) -> Any? {
        // If not optional return value
        guard let optional = any as? SGYOptionalReflection else { return any }
        // Must wrap a non-nil
        guard let wrappedValue = optional.wrappedValue else { return nil }
        // Could have returned Optional as the non-nil, so recursively call again
        return unwrap(wrappedValue)
    }
}