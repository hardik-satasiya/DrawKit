/**
 @author Contributions from the community; see CONTRIBUTORS.md
 @date 2005-2016
 @copyright MPL2; see LICENSE.txt
*/

#import "DKCategoryManager.h"
#import "DKUnarchivingHelper.h"
#import "LogEvent.h"
#import "NSDictionary+DeepCopy.h"
#import "NSMutableArray+DKAdditions.h"
#import "NSString+DKAdditions.h"

#pragma mark Contants(Non - localized)
NSString* const kDKDefaultCategoryName = @"All Items";
NSString* const kDKRecentlyAddedUserString = @"Recently Added";
NSString* const kDKRecentlyUsedUserString = @"Recently Used";

NSString* const kDKCategoryManagerWillAddObject = @"kDKCategoryManagerWillAddObject";
NSString* const kDKCategoryManagerDidAddObject = @"kDKCategoryManagerDidAddObject";
NSString* const kDKCategoryManagerWillRemoveObject = @"kDKCategoryManagerWillRemoveObject";
NSString* const kDKCategoryManagerDidRemoveObject = @"kDKCategoryManagerDidRemoveObject";
NSString* const kDKCategoryManagerDidRenameCategory = @"kDKCategoryManagerDidRenameCategory";
NSString* const kDKCategoryManagerWillAddKeyToCategory = @"kDKCategoryManagerWillAddKeyToCategory";
NSString* const kDKCategoryManagerDidAddKeyToCategory = @"kDKCategoryManagerDidAddKeyToCategory";
NSString* const kDKCategoryManagerWillRemoveKeyFromCategory = @"kDKCategoryManagerWillRemoveKeyFromCategory";
NSString* const kDKCategoryManagerDidRemoveKeyFromCategory = @"kDKCategoryManagerDidRemoveKeyFromCategory";
NSString* const kDKCategoryManagerWillCreateNewCategory = @"kDKCategoryManagerWillCreateNewCategory";
NSString* const kDKCategoryManagerDidCreateNewCategory = @"kDKCategoryManagerDidCreateNewCategory";
NSString* const kDKCategoryManagerWillDeleteCategory = @"kDKCategoryManagerWillDeleteCategory";
NSString* const kDKCategoryManagerDidDeleteCategory = @"kDKCategoryManagerDidDeleteCategory";

/** @brief private object used to store menu info - allows efficient management of the menu to match the C/Mgrs contents.
 
 Menu creation and management is moved to this class, but API in Cat Manager functions as previously.
 */
@interface DKCategoryManagerMenuInfo : NSObject {
@private
	DKCategoryManager* mCatManagerRef; // the category manager that owns this
	NSMenu* mTheMenu; // the menu being managed
	__unsafe_unretained id mTargetRef; // initial target for new menu items
	__unsafe_unretained id<DKCategoryManagerMenuItemDelegate> mCallbackTargetRef; // delegate for menu items
	SEL mSelector; // initial action for new menu items
	DKCategoryMenuOptions mOptions; // option flags
	BOOL mCategoriesOnly; // YES if the menu just lists the categories and not the category contents
	NSMenuItem* mRecentlyUsedMenuItemRef; // the menu item for "recently used"
	NSMenuItem* mRecentlyAddedMenuItemRef; // the menu item for "recently added"
}

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (instancetype)initWithCategoryManager:(DKCategoryManager*)mgr itemTarget:(nullable id)target itemAction:(nullable SEL)selector options:(DKCategoryMenuOptions)options NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCategoryManager:(DKCategoryManager*)mgr itemDelegate:(id<DKCategoryManagerMenuItemDelegate>)delegate options:(DKCategoryMenuOptions)options NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCategoryManager:(DKCategoryManager*)mgr itemDelegate:(id<DKCategoryManagerMenuItemDelegate>)delegate itemTarget:(nullable id)target itemAction:(nullable SEL)selector options:(DKCategoryMenuOptions)options NS_DESIGNATED_INITIALIZER;

- (NSMenu*)menu;

- (void)addCategory:(DKCategoryName)newCategory;
- (void)removeCategory:(DKCategoryName)oldCategory;
- (void)renameCategoryWithInfo:(NSDictionary<NSString*, DKCategoryName>*)info;
- (void)addKey:(NSString*)aKey;
- (void)addRecentlyAddedOrUsedKey:(NSString*)aKey;
- (void)syncRecentlyUsedMenuForKey:(NSString*)aKey;
- (void)removeKey:(NSString*)aKey;
- (void)checkItemsForKey:(NSString*)key;
- (void)updateForKey:(NSString*)key;
- (void)removeAll;

@end

// this tag is set in every menu item that we create/manage automatically. Normally client code of the menus shouldn't use the tags of these items but instead the represented object,
// so this tag identifies items that we can freely discard or modify. Any others are left alone, allowing clients to add other items to the menus that won't get disturbed.

enum {
	kDKCategoryManagerManagedMenuItemTag = -42,
	kDKCategoryManagerRecentMenuItemTag = -43
};

@interface DKCategoryManager ()

- (nullable DKCategoryManagerMenuInfo*)findInfoForMenu:(NSMenu*)aMenu;

@end

#pragma mark -
@implementation DKCategoryManager
#pragma mark As a DKCategoryManager

static id sDearchivingHelper = nil;

+ (DKCategoryManager*)categoryManager
{
	return [[DKCategoryManager alloc] init];
}

+ (DKCategoryManager*)categoryManagerWithDictionary:(NSDictionary*)dict
{
	return [[DKCategoryManager alloc] initWithDictionary:dict];
}

+ (NSArray*)defaultCategories
{
	return @[kDKDefaultCategoryName];
}

+ (NSString*)categoryManagerKeyForObject:(id)obj
{
#pragma unused(obj)

	NSLog(@"warning - subclasses of DKCategoryManager must override +categoryManagerKeyForObject: to correctly implement merging");

	return nil;
}

+ (id)dearchivingHelper
{
	if (sDearchivingHelper == nil)
		sDearchivingHelper = [[DKUnarchivingHelper alloc] init];

	return sDearchivingHelper;
}

+ (void)setDearchivingHelper:(id)helper
{
	sDearchivingHelper = helper;
}

#pragma mark -
#pragma mark - initialization

- (instancetype)initWithData:(NSData*)data
{
	NSAssert(data != nil, @"Expected valid data");

	NSKeyedUnarchiver* unarch = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];

	// in order to translate older files with classes named 'GC' instead of 'DK', need a delegate that can handle the
	// translation. Apps can also swap out this helper, or become listeners of its notifications for progress indication

	id dearchivingHelper = [[self class] dearchivingHelper];
	if ([dearchivingHelper respondsToSelector:@selector(reset)])
		[dearchivingHelper reset];

	[unarch setDelegate:dearchivingHelper];
	id obj = [unarch decodeObjectForKey:@"root"];

	[unarch finishDecoding];

	NSAssert(obj != nil, @"Expected valid obj");

	if ([obj isKindOfClass:[DKCategoryManager class]]) // not [self class] as cat mgr is sometimes subclassed
	{
		DKCategoryManager* cm = (DKCategoryManager*)obj;

		self = [self init];
		if (self) {
			[m_masterList setDictionary:cm->m_masterList];
			[m_categories setDictionary:cm->m_categories];
			[m_recentlyAdded setArray:cm->m_recentlyAdded];
			[m_recentlyUsed setArray:cm->m_recentlyUsed];

			m_maxRecentlyUsedItems = cm->m_maxRecentlyUsedItems;
			m_maxRecentlyAddedItems = cm->m_maxRecentlyAddedItems;
		}
	} else if ([obj isKindOfClass:[NSDictionary class]]) {
		self = [self initWithDictionary:obj];
	} else {
		self = [self init];
		NSLog(@"%@ ! data was not a valid archive for -initWithData:", self);
	}
	return self;
}

- (instancetype)initWithDictionary:(NSDictionary*)dict
{
	NSAssert(dict != nil, @"Expected valid dict");
	self = [self init];
	if (self != nil) {
		// dictionary keys need to be all lowercase to allow "case insensitivity" in the master list

		for (NSString* s in dict) {
			id obj = [dict objectForKey:s];
			[m_masterList setObject:obj
							 forKey:[s lowercaseString]];
		}

		// add to "All Items":

		NSMutableArray* aicat = [m_categories objectForKey:kDKDefaultCategoryName];

		if (aicat) {
			[aicat addObjectsFromArray:[dict allKeys]];
		}
	}

	return self;
}

#pragma mark -
#pragma mark - adding and retrieving objects

- (void)addObject:(id)obj forKey:(NSString*)name toCategory:(NSString*)catName createCategory:(BOOL)cg
{
	//	LogEvent_(kStateEvent, @"category manager adding object:%@ name:%@ to category:%@", obj, name, catName );

	NSAssert(obj != nil, @"object cannot be nil");
	NSAssert(name != nil, @"name cannot be nil");
	NSAssert([name length] > 0, @"name cannot be empty");

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerWillAddObject
														object:self];

	// add the object to the master list

	[m_masterList setObject:obj
					 forKey:[name lowercaseString]];
	[self addKey:name
		toRecentList:kDKListRecentlyAdded];

	// add to single category specified if any

	if (catName != nil)
		[self addKey:name
				toCategory:catName
			createCategory:cg];

	[self addKey:name
			toCategory:kDKDefaultCategoryName
		createCategory:NO];

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerDidAddObject
														object:self];
}

- (void)addObject:(id)obj forKey:(NSString*)name toCategories:(NSArray*)catNames createCategories:(BOOL)cg
{
	//	LogEvent_(kStateEvent, @"category manager adding object:%@ name:%@ to categories:%@", obj, name, catNames );

	NSAssert(obj != nil, @"object cannot be nil");
	NSAssert(name != nil, @"name cannot be nil");
	NSAssert([name length] > 0, @"name cannot be empty");

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerWillAddObject
														object:self];

	// add the object to the master list

	[m_masterList setObject:obj
					 forKey:[name lowercaseString]];
	[self addKey:name
		toRecentList:kDKListRecentlyAdded];

	// add to multiple categories specified

	if (catNames != nil && [catNames count] > 0)
		[self addKey:name
				toCategories:catNames
			createCategories:cg];

	[self addKey:name
			toCategory:kDKDefaultCategoryName
		createCategory:NO];

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerDidAddObject
														object:self];
}

- (void)removeObjectForKey:(NSString*)key
{
	// remove this key from any/all categories and lists

	NSAssert(key != nil, @"attempt to remove nil key");

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerWillRemoveObject
														object:self];

	[self removeKeyFromAllCategories:key];
	[self removeKey:key
		fromRecentList:kDKListRecentlyAdded];
	[self removeKey:key
		fromRecentList:kDKListRecentlyUsed];

	// remove from master dictionary

	[m_masterList removeObjectForKey:[key lowercaseString]];
	[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerDidRemoveObject
														object:self];
}

- (void)removeObjectsForKeys:(NSArray*)keys
{
	for (NSString* key in keys)
		[self removeObjectForKey:key];
}

- (void)removeAllObjects
{
	NSArray* keys = [self allKeys];
	[self removeObjectsForKeys:keys];
}

#pragma mark -

- (BOOL)containsKey:(NSString*)key
{
	return [[m_masterList allKeys] containsObject:[key lowercaseString]];
}

- (NSUInteger)count
{
	return [m_masterList count];
}

#pragma mark -

- (id)objectForKey:(NSString*)key
{
	return [m_masterList objectForKey:[key lowercaseString]];
}

- (id)objectForKey:(NSString*)key addToRecentlyUsedItems:(BOOL)add
{
	// returns the object, but optionally adds it to the "recently used" list

	id obj = [self objectForKey:key];

	if (add)
		[self addKey:key
			toRecentList:kDKListRecentlyUsed];

	return obj;
}

#pragma mark -

- (NSArray*)keysForObject:(id)obj
{
	//return [[self dictionary] allKeysForObject:obj];  // doesn't work because master dict uses lowercase keys

	NSMutableArray* keys = [[NSMutableArray alloc] init];

	for (NSString* key in [self allKeys]) {
		if ([[self objectForKey:key] isEqual:obj])
			[keys addObject:key];
	}

	return keys;
}

- (NSDictionary*)dictionary
{
	return [m_masterList copy];
}

- (NSSet*)mergeObjectsFromSet:(NSSet*)aSet inCategories:(NSArray*)categories mergeOptions:(DKCatManagerMergeOptions)options mergeDelegate:(id)aDelegate
{
	NSAssert(aSet != nil, @"cannot merge - set was nil");

	id existingObj;
	NSMutableSet* changedStyles = nil;
	NSString* key;

	for (id obj in aSet) {
		// if the style is unknown to the registry, simply register it - in this case there's no need to do any complex merging or
		// further analysis.

		key = [[self class] categoryManagerKeyForObject:obj];
		existingObj = [self objectForKey:key];

		if (existingObj == nil)
			[self addObject:obj
						  forKey:key
					toCategories:categories
				createCategories:YES];
		else {
			if ((options & kDKReplaceExisting) != 0) {
				// style is known to us, so a merge is required, overwriting the registered object with the new one. Any clients of the
				// modified style will be updated automatically.

				existingObj = [self mergeObject:obj
								  mergeDelegate:aDelegate];

				if (existingObj != nil) {
					if (changedStyles == nil)
						changedStyles = [NSMutableSet set];

					[changedStyles addObject:existingObj];

					// add to the requested categories if needed

					[self addKey:key
							toCategories:categories
						createCategories:YES];
				}
			} else if ((options & kDKReturnExisting) != 0) {
				// here the options request that the registered styles have priority, so the existing style is added to the return set

				if (changedStyles == nil)
					changedStyles = [NSMutableSet set];

				[changedStyles addObject:existingObj];

				// add to the requested categories if needed

				[self addKey:key
						toCategories:categories
					createCategories:YES];
			} else if ((options & kDKAddAsNewVersions) != 0) {
				// here the options request that the document styles are to be re-registered as new styles. This leaves both document and
				// existing registered styles unaffected but can massively multiply the registry with many duplicates. In general this
				// options should be used sparingly, if at all.

				// TO DO

				// there's nothing to return in this case
			}
		}
	}

	return changedStyles;
}

- (id)mergeObject:(id)obj mergeDelegate:(id<DKCategoryManagerMergeDelegate>)aDelegate
{
	NSAssert(obj != nil, @"cannot merge - object was nil");

	id newObj = nil;

	if (aDelegate && [aDelegate respondsToSelector:@selector(categoryManager:shouldReplaceObject:withObject:)]) {
		id existingObject = [self objectForKey:[[self class] categoryManagerKeyForObject:obj]];

		if (existingObject == nil || existingObject == obj)
			return nil; // this is really an error - the object is already registered, or is unregistered

		// ask the delegate:

		newObj = [aDelegate categoryManager:self
						shouldReplaceObject:existingObject
								 withObject:obj];
	}

	return newObj;
}

#pragma mark -
#pragma mark - retrieving lists of objects by category

- (NSArray*)objectsInCategory:(NSString*)catName
{
	NSMutableArray* keys = [[NSMutableArray alloc] init];

	for (NSString* s in [self allKeysInCategory:catName])
		[keys addObject:[s lowercaseString]];

	return [m_masterList objectsForKeys:keys
						 notFoundMarker:[NSNull null]];
}

- (NSArray*)objectsInCategories:(NSArray*)catNames
{
	NSMutableArray* keys = [[NSMutableArray alloc] init];

	for (NSString* s in [self allKeysInCategories:catNames])
		[keys addObject:[s lowercaseString]];

	return [m_masterList objectsForKeys:keys
						 notFoundMarker:[NSNull null]];
}

- (NSArray*)allKeysInCategory:(NSString*)catName
{
	if ([catName isEqualToString:kDKRecentlyAddedUserString])
		return [self recentlyAddedItems];
	else if ([catName isEqualToString:kDKRecentlyUsedUserString])
		return [self recentlyUsedItems];
	else
		return [m_categories objectForKey:catName];
}

- (NSArray*)allKeysInCategories:(NSArray*)catNames
{
	if ([catNames count] == 1)
		return [self allKeysInCategory:[catNames lastObject]];
	else {
		NSMutableArray* temp = [[NSMutableArray alloc] init];
		NSArray* keys;

		for (NSString* catname in catNames) {
			keys = [self allKeysInCategory:catname];

			// add keys not already in <temp> to temp

			[temp addUniqueObjectsFromArray:keys];
		}

		return temp;
	}
}

- (NSArray*)allKeys
{
	//return [[self dictionary] allKeys];		// doesn't work because keys are lowercase

	return [self allKeysInCategories:[self allCategories]];
}

- (NSArray*)allObjects
{
	return [m_masterList allValues];
}

- (NSArray*)allSortedKeysInCategory:(NSString*)catName
{
	return [[self allKeysInCategory:catName] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

- (NSArray*)allSortedNamesInCategory:(NSString*)catName
{
	return [self allSortedKeysInCategory:catName];
}

#pragma mark -

- (void)setRecentlyAddedItems:(NSArray*)array
{
	[m_recentlyAdded removeAllObjects];

	NSUInteger i;

	for (i = 0; i < MIN([array count], m_maxRecentlyAddedItems); ++i)
		[m_recentlyAdded addObject:[array objectAtIndex:i]];
}

- (NSArray*)recentlyAddedItems
{
	return m_recentlyAdded;
}

- (NSArray*)recentlyUsedItems
{
	return m_recentlyUsed;
}

#pragma mark -
#pragma mark - category management - creating, deleting and renaming categories

- (void)addDefaultCategories
{
	[self addCategories:[self defaultCategories]];
}

- (NSArray*)defaultCategories
{
	return [[self class] defaultCategories];
}

- (void)addCategory:(NSString*)catName
{
	if ([m_categories objectForKey:catName] == nil) {
		//	LogEvent_(kStateEvent,  @"adding new category '%@'", catName );

		NSMutableArray* cat = [[NSMutableArray alloc] init];
		NSDictionary* info = @{ @"category_name": catName };

		[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerWillCreateNewCategory
															object:self
														  userInfo:info];
		[m_categories setObject:cat
						 forKey:catName];

		// inform any menus of the new category

		[mMenusList makeObjectsPerformSelector:@selector(addCategory:)
									withObject:catName];
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerDidCreateNewCategory
															object:self
														  userInfo:info];
	}
}

- (void)addCategories:(NSArray*)catNames
{
	for (NSString* catName in catNames)
		[self addCategory:catName];
}

- (void)removeCategory:(NSString*)catName
{
	//	LogEvent_(kStateEvent, @"removing category '%@'", catName );

	if ([m_categories objectForKey:catName]) {
		NSDictionary* info = @{ @"category_name": catName };

		[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerWillDeleteCategory
															object:self
														  userInfo:info];
		[m_categories removeObjectForKey:catName];

		// inform menus that category has gone

		[mMenusList makeObjectsPerformSelector:@selector(removeCategory:)
									withObject:catName];
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerDidDeleteCategory
															object:self
														  userInfo:info];
	}
}

- (void)renameCategory:(NSString*)catName to:(NSString*)newname
{
	LogEvent_(kStateEvent, @"renaming the category '%@' to' %@'", catName, newname);

	NSMutableArray* gs = [m_categories objectForKey:catName];

	if (gs) {
		[m_categories removeObjectForKey:catName];

		[m_categories setObject:gs
						 forKey:newname];

		// update menu item title:

		NSDictionary* info = @{ @"old_name": catName,
			@"new_name": newname };
		[mMenusList makeObjectsPerformSelector:@selector(renameCategoryWithInfo:)
									withObject:info];

		[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerDidRenameCategory
															object:self];
	}
}

- (void)removeAllCategories
{
	[m_masterList removeAllObjects];
	[m_categories removeAllObjects];
	[m_recentlyUsed removeAllObjects];
	[m_recentlyAdded removeAllObjects];

	[mMenusList makeObjectsPerformSelector:@selector(removeAll)];
}

#pragma mark -

- (void)addKey:(NSString*)key toCategory:(NSString*)catName createCategory:(BOOL)cg
{
	// add a key to an existing group, or to a new group if it doesn't yet exist and the flag is set

	NSAssert(key != nil, @"key can't be nil");

	if (catName == nil)
		return;

	LogEvent_(kStateEvent, @"category manager adding key '%@' to category '%@'", key, catName);

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerWillAddKeyToCategory
														object:self];

	NSMutableArray* ga = [m_categories objectForKey:catName];

	if (ga == nil && cg) {
		// doesn't exist - create it

		[self addCategory:catName];
		ga = [m_categories objectForKey:catName];
	}

	// add the key to this group's list if not already known

	if (![ga containsObject:key]) {
		[ga addObject:key];

		// update menus

		[mMenusList makeObjectsPerformSelector:@selector(addKey:)
									withObject:key];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerDidAddKeyToCategory
														object:self];
}

- (void)addKey:(NSString*)key toCategories:(NSArray*)catNames createCategories:(BOOL)cg
{
	if (catNames == nil)
		return;

	for (NSString* cat in catNames)
		[self addKey:key
				toCategory:cat
			createCategory:cg];
}

- (void)removeKey:(NSString*)key fromCategory:(NSString*)catName
{
	//	LogEvent_(kStateEvent, @"removing key '%@' from category '%@'", key, catName );

	NSMutableArray* ga = [m_categories objectForKey:catName];

	if (ga) {
		// remove from menus - do this first so that the menus are still able to look up category membership
		// of the object

		[mMenusList makeObjectsPerformSelector:@selector(removeKey:)
									withObject:key];

		[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerWillRemoveKeyFromCategory
															object:self];
		[ga removeObject:key];
		[[NSNotificationCenter defaultCenter] postNotificationName:kDKCategoryManagerDidRemoveKeyFromCategory
															object:self];
	}
}

- (void)removeKey:(NSString*)key fromCategories:(NSArray*)catNames
{
	if (catNames == nil)
		return;

	for (NSString* cat in catNames)
		[self removeKey:key
			fromCategory:cat];
}

- (void)removeKeyFromAllCategories:(NSString*)key
{
	[self removeKey:key
		fromCategories:[self allCategories]];
}

- (void)fixUpCategories
{
	for (NSString* key in [self allKeys]) {
		if ([self objectForKey:key] == nil)
			[self removeKeyFromAllCategories:key];
	}
}

- (void)renameKey:(NSString*)key to:(NSString*)newKey
{
	NSAssert(key != nil, @"expected non-nil key");
	NSAssert(newKey != nil, @"expected non-nil new key");

	// if the keys are the same, do nothing

	if ([key isEqualToString:newKey])
		return;

	// first check that <key> exists:

	if (![self containsKey:key])
		[NSException raise:NSInvalidArgumentException
					format:@"The key '%@' can't be renamed because it doesn't exist", key];

	// check that the new key isn't in use:

	if ([self containsKey:newKey])
		[NSException raise:NSInvalidArgumentException
					format:@"Cannot rename key to '%@' because that key is already in use", newKey];

	LogEvent_(kStateEvent, @"changing key '%@' to '%@'", key, newKey);

	// what categories are going to be touched?

	NSArray* cats = [self categoriesContainingKey:key];

	// retain the object while we move it around:

	id object = [self objectForKey:key];
	[self removeObjectForKey:key];
	[self addObject:object
				  forKey:newKey
			toCategories:cats
		createCategories:NO];
}

#pragma mark -
#pragma mark - getting lists, etc.of the categories

- (NSArray*)allCategories
{
	return [[m_categories allKeys] sortedArrayUsingSelector:@selector(localisedCaseInsensitiveNumericCompare:)];
}

- (NSUInteger)countOfCategories
{
	return [m_categories count];
}

- (NSArray*)categoriesContainingKey:(NSString*)key
{
	return [self categoriesContainingKey:key
							 withSorting:YES];
}

- (NSArray*)categoriesContainingKey:(NSString*)key withSorting:(BOOL)sortIt
{
	NSMutableArray* catList;

	catList = [[NSMutableArray alloc] init];

	for (NSString* catName in [m_categories allKeys]) {
		NSArray* cat = [self allKeysInCategory:catName];

		if ([cat containsObject:key])
			[catList addObject:catName];
	}

	if (sortIt)
		[catList sortUsingSelector:@selector(caseInsensitiveCompare:)];

	return catList;
}

/** @brief Get a list of reserved categories - those that should not be deleted or renamed

 This list is advisory - a UI is responsible for honouring it, the cat manager itself ignores it.
 The default implementation returns the same as the default categories, thus reserving all
 default cats. Subclasses can change this as they wish.
 @return an array containing a list of the reserved categories
 */
- (NSArray*)reservedCategories
{
	return [self defaultCategories];
}

#pragma mark -

- (BOOL)categoryExists:(NSString*)catName
{
	return [m_categories objectForKey:catName] != nil;
}

- (NSUInteger)countOfObjectsInCategory:(NSString*)catName
{
	return [[m_categories objectForKey:catName] count];
}

- (BOOL)key:(NSString*)key existsInCategory:(NSString*)catName
{
	return [[m_categories objectForKey:catName] containsObject:key];
}

#pragma mark -
#pragma mark - managing recent lists

- (void)setRecentlyAddedListEnabled:(BOOL)enable
{
	mRecentlyAddedEnabled = enable;
}

- (BOOL)addKey:(NSString*)key toRecentList:(NSInteger)whichList
{
	NSUInteger max;
	NSMutableArray* rl;
	BOOL movedOnly = NO;

	switch (whichList) {
	case kDKListRecentlyAdded:
		rl = m_recentlyAdded;
		max = m_maxRecentlyAddedItems;

		if (!mRecentlyAddedEnabled)
			return NO;

		break;

	case kDKListRecentlyUsed:
		rl = m_recentlyUsed;
		max = m_maxRecentlyUsedItems;
		if ([rl containsObject:key]) {
			[rl removeObject:key]; // forces reinsertion of the key at the head of the list
			movedOnly = YES;
		}
		break;

	default:
		return NO;
	}

	if (![rl containsObject:key]) {
		[rl insertObject:key
				 atIndex:0];
		while ([rl count] > max)
			[rl removeLastObject];

		// manage the menus as required (will remove and add items to keep menu in synch. with array)

		if (!movedOnly)
			[mMenusList makeObjectsPerformSelector:@selector(addRecentlyAddedOrUsedKey:)
										withObject:key];
		else
			[mMenusList makeObjectsPerformSelector:@selector(syncRecentlyUsedMenuForKey:)
										withObject:key];

		return YES;
	}

	return NO;
}

- (void)removeKey:(NSString*)key fromRecentList:(NSInteger)whichList
{
	NSMutableArray* rl;

	switch (whichList) {
	case kDKListRecentlyAdded:
		rl = m_recentlyAdded;
		break;

	case kDKListRecentlyUsed:
		rl = m_recentlyUsed;
		break;

	default:
		return;
	}

	[rl removeObject:key];

	// remove items(s) from managed menus also

	[mMenusList makeObjectsPerformSelector:@selector(addRecentlyAddedOrUsedKey:)
								withObject:nil];
}

- (void)setRecentList:(NSInteger)whichList maxItems:(NSUInteger)max
{
	switch (whichList) {
	case kDKListRecentlyAdded:
		m_maxRecentlyAddedItems = max;
		break;

	case kDKListRecentlyUsed:
		m_maxRecentlyUsedItems = max;
		break;

	default:
		return;
	}
}

#pragma mark -
#pragma mark - archiving

- (NSData*)data
{
	return [self dataWithFormat:NSPropertyListXMLFormat_v1_0];
}

- (NSData*)dataWithFormat:(NSPropertyListFormat)format
{
	NSMutableData* d = [NSMutableData dataWithCapacity:100];
	NSKeyedArchiver* arch = [[NSKeyedArchiver alloc] initForWritingWithMutableData:d];

	[arch setOutputFormat:format];

	[self fixUpCategories]; // avoid archiving a badly formed object
	[arch encodeObject:self
				forKey:@"root"];
	[arch finishEncoding];

	return d;
}

- (NSString*)fileType
{
	return @"dkcatmgr";
}

- (BOOL)replaceContentsWithData:(NSData*)data
{
	NSAssert(data != nil, @"cannot replace from nil data");

	DKCategoryManager* newCM = [[[self class] alloc] initWithData:data];

	if (newCM) {
		// since we are completely replacing, we can just transfer the master containers straight over without iterating over
		// all the individual items. This should be a lot faster.

		//NSLog(@"%@ replacing CM content from %@", self, newCM );

		[m_masterList setDictionary:newCM->m_masterList];
		[m_categories setDictionary:newCM->m_categories];
		[m_recentlyUsed setArray:newCM->m_recentlyUsed];
		[m_recentlyAdded setArray:newCM->m_recentlyAdded];

		// TODO: deal with menus

		[self setRecentlyAddedListEnabled:YES];

		return YES;
	}

	return NO;
}

- (BOOL)appendContentsWithData:(NSData*)data
{
	NSAssert(data != nil, @"cannot append from nil data");

	DKCategoryManager* newCM = [[[self class] alloc] initWithData:data];

	if (newCM) {
		[self copyItemsFromCategoryManager:newCM];

		return YES;
	}

	return NO;
}

- (void)copyItemsFromCategoryManager:(DKCategoryManager*)cm
{
	NSAssert(cm != nil, @"cannot copy items from nil");

	NSArray* newCategories;
	NSArray* newObjects = [cm allKeys];

	[self setRecentlyAddedListEnabled:NO];

	for (NSString* key in newObjects) {
		id obj = [cm objectForKey:key];
		newCategories = [cm categoriesContainingKey:key
										withSorting:NO];
		[self addObject:obj
					  forKey:key
				toCategories:newCategories
			createCategories:YES];
	}

	[self setRecentlyAddedListEnabled:YES];
	[self setRecentlyAddedItems:[cm recentlyAddedItems]];
}

#pragma mark -
#pragma mark - supporting UI

- (DKCategoryManagerMenuInfo*)findInfoForMenu:(NSMenu*)aMenu
{
	// private method - returns the management object for the given menu

	for (DKCategoryManagerMenuInfo* menuInfo in mMenusList) {
		if ([menuInfo menu] == aMenu)
			return menuInfo;
	}

	return nil;
}

- (void)removeMenu:(NSMenu*)menu
{
	[mMenusList removeObject:[self findInfoForMenu:menu]];
}

- (void)updateMenusForKey:(NSString*)key
{
	[mMenusList makeObjectsPerformSelector:@selector(updateForKey:)
								withObject:key];
}

#pragma mark - a menu with everything, organised hierarchically by category

- (NSMenu*)createMenuWithItemDelegate:(id)del isPopUpMenu:(BOOL)isPopUp
{
	NSInteger options = kDKIncludeRecentlyAddedItems | kDKIncludeRecentlyUsedItems;

	if (isPopUp)
		options |= kDKMenuIsPopUpMenu;

	return [self createMenuWithItemDelegate:del
									options:options];
}

- (NSMenu*)createMenuWithItemDelegate:(id)del options:(DKCategoryMenuOptions)options
{
	return [self createMenuWithItemDelegate:del
								 itemTarget:nil
								 itemAction:NULL
									options:options];
}

- (NSMenu*)createMenuWithItemDelegate:(id)del itemTarget:(id)target itemAction:(SEL)action options:(DKCategoryMenuOptions)options
{
	DKCategoryManagerMenuInfo* menuInfo;

	menuInfo = [[DKCategoryManagerMenuInfo alloc] initWithCategoryManager:self
															 itemDelegate:del
															   itemTarget:target
															   itemAction:action
																  options:options];

	[mMenusList addObject:menuInfo];

	return [menuInfo menu];
}

#pragma mark - menus of just the categories

- (NSMenu*)categoriesMenuWithSelector:(SEL)sel target:(id)target
{
	return [self categoriesMenuWithSelector:sel
									 target:target
									options:kDKIncludeRecentlyAddedItems | kDKIncludeRecentlyUsedItems | kDKIncludeAllItems];
}

- (NSMenu*)categoriesMenuWithSelector:(SEL)sel target:(id)target options:(DKCategoryMenuOptions)options
{
	// create and populate a menu with the category names plus optionally the recent items lists

	DKCategoryManagerMenuInfo* menuInfo = [[DKCategoryManagerMenuInfo alloc] initWithCategoryManager:self
																						  itemTarget:target
																						  itemAction:sel
																							 options:options];

	[mMenusList addObject:menuInfo];

	return [menuInfo menu];
}

- (void)checkItemsInMenu:(NSMenu*)menu forCategoriesContainingKey:(NSString*)key
{
	DKCategoryManagerMenuInfo* menuInfo = [self findInfoForMenu:menu];

	if (menuInfo)
		[menuInfo checkItemsForKey:key];
}

#pragma mark -
#pragma mark As an NSObject
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		m_masterList = [[NSMutableDictionary alloc] init];
		m_categories = [[NSMutableDictionary alloc] init];
		m_recentlyAdded = [[NSMutableArray alloc] init];
		m_recentlyUsed = [[NSMutableArray alloc] init];
		mMenusList = [[NSMutableArray alloc] init];
		mRecentlyAddedEnabled = YES;
		m_maxRecentlyAddedItems = kDKDefaultMaxRecentArraySize;
		m_maxRecentlyUsedItems = kDKDefaultMaxRecentArraySize;

		if (m_masterList == nil
			|| m_categories == nil
			|| m_recentlyAdded == nil
			|| m_recentlyUsed == nil) {
			return nil;
		}
		// add the default categories

		[self addDefaultCategories];
	}
	return self;
}

#pragma mark -
#pragma mark As part of NSCoding Protocol
- (void)encodeWithCoder:(NSCoder*)coder
{
	[coder encodeObject:m_masterList
				 forKey:@"master"];
	[coder encodeObject:m_categories
				 forKey:@"categories"];
	[coder encodeObject:m_recentlyAdded
				 forKey:@"recent_add"];
	[coder encodeObject:m_recentlyUsed
				 forKey:@"recent_use"];

	[coder encodeInteger:m_maxRecentlyAddedItems
				  forKey:@"maxadd"];
	[coder encodeInteger:m_maxRecentlyUsedItems
				  forKey:@"maxuse"];
}

- (instancetype)initWithCoder:(NSCoder*)coder
{
	if (self = [super init]) {
		m_masterList = [coder decodeObjectForKey:@"master"];
		m_categories = [coder decodeObjectForKey:@"categories"];
		m_recentlyAdded = [coder decodeObjectForKey:@"recent_add"];
		m_recentlyUsed = [coder decodeObjectForKey:@"recent_use"];

		m_maxRecentlyAddedItems = [coder decodeIntegerForKey:@"maxadd"];
		m_maxRecentlyUsedItems = [coder decodeIntegerForKey:@"maxuse"];
		mRecentlyAddedEnabled = YES;

		mMenusList = [[NSMutableArray alloc] init];

		if (m_masterList == nil
			|| m_categories == nil
			|| m_recentlyAdded == nil
			|| m_recentlyUsed == nil) {
			return nil;
		}
	}

	return self;
}

#pragma mark -
#pragma mark As part of NSCopying protocol

- (id)copyWithZone:(NSZone*)zone
{
	// a copy of the category manager has the same objects, a deep copy of the categories, but empty recent lists.
	// it also doesn't copy the menu management data across. Thus the copy has the same data structure as this, but lacks the
	// dynamic information that pertains to current usage and UI. The copy can be used as a "fork" of this CM.

	DKCategoryManager* copy = [[[self class] allocWithZone:zone] init];

	[copy->m_masterList setDictionary:m_masterList];

	NSDictionary* cats = [m_categories deepCopy];
	[copy->m_categories setDictionary:cats];

	return copy;
}

@end

#pragma mark -
#pragma mark DKCategoryManagerMenuInfo

@interface DKCategoryManagerMenuInfo ()

- (void)createMenu;
- (void)createCategoriesMenu;
- (NSMenu*)createSubmenuWithTitle:(NSString*)title forArray:(NSArray<NSString*>*)items;
- (void)removeItemsInMenu:(NSMenu*)aMenu withTag:(NSInteger)tag excludingItem0:(BOOL)title;

@end

@implementation DKCategoryManagerMenuInfo

- (instancetype)initWithCategoryManager:(DKCategoryManager*)mgr itemTarget:(id)target itemAction:(SEL)selector options:(DKCategoryMenuOptions)options
{
	self = [super init];
	if (self != nil) {
		mCatManagerRef = mgr;
		mTargetRef = target;
		mSelector = selector;
		mOptions = options;
		mCategoriesOnly = YES;
		[self createCategoriesMenu];
	}

	return self;
}

- (instancetype)initWithCategoryManager:(DKCategoryManager*)mgr itemDelegate:(id)delegate options:(DKCategoryMenuOptions)options
{
	NSAssert(delegate != nil, @"no delegate for menu item callback");

	self = [super init];
	if (self != nil) {
		mCatManagerRef = mgr;
		mCallbackTargetRef = delegate;
		mOptions = options;
		mCategoriesOnly = NO;
		[self createMenu];
	}

	return self;
}

- (instancetype)initWithCategoryManager:(DKCategoryManager*)mgr itemDelegate:(id<DKCategoryManagerMenuItemDelegate>)delegate itemTarget:(id)target itemAction:(SEL)selector options:(DKCategoryMenuOptions)options
{
	NSAssert(delegate != nil, @"no delegate for menu item callback");

	self = [super init];
	if (self != nil) {
		mCatManagerRef = mgr;
		mCallbackTargetRef = delegate;
		mTargetRef = target;
		mSelector = selector;
		mOptions = options;
		mCategoriesOnly = NO;
		[self createMenu];
	}

	return self;
}

- (NSMenu*)menu
{
	return mTheMenu;
}

- (void)addCategory:(NSString*)newCategory
{
	LogEvent_(kInfoEvent, @"adding category '%@' to menu %@", newCategory, self);

	// adds a new parent item to the main menu with the given category name and creates an empty submenu. The item is inserted into the menu
	// at the appropriate position to maintain alphabetical order. If the category already exists as a menu item, this does nothing.

	// known?

	NSInteger indx = [mTheMenu indexOfItemWithTitle:[newCategory capitalizedString]];

	if (indx == -1) {
		// prepare the new menu

		NSMenuItem* newItem = [[NSMenuItem alloc] initWithTitle:[newCategory capitalizedString]
														 action:mSelector
												  keyEquivalent:@""];

		// disable the item if it has a submenu but no items

		[newItem setEnabled:mCategoriesOnly];
		[newItem setTarget:mTargetRef];
		[newItem setAction:mSelector];
		[newItem setTag:kDKCategoryManagerManagedMenuItemTag];

		// find where to insert it and do so. The categories already contains this item, so we can just sort then find it.

		NSArray* temp = [mCatManagerRef allCategories];
		indx = [temp indexOfObject:newCategory];

		if (indx == NSNotFound)
			indx = 0;

		if (mOptions & kDKIncludeAllItems)
			++indx; // +1 allows for hidden title item unless we skipped "All Items"

		if (mCategoriesOnly) {
			--indx; // we're off by 1 somewhere

			if (mOptions & kDKIncludeRecentlyUsedItems)
				++indx;

			if (mOptions & kDKIncludeRecentlyAddedItems)
				++indx;

			if ((mOptions & kDKDontAddDividingLine) == 0)
				++indx;
		}
		if (indx > [mTheMenu numberOfItems])
			indx = [mTheMenu numberOfItems];

		[mTheMenu insertItem:newItem
					 atIndex:indx];
	}
}

- (void)removeCategory:(NSString*)oldCategory
{
	LogEvent_(kInfoEvent, @"removing category '%@' from menu %@", oldCategory, self);

	NSMenuItem* item = [mTheMenu itemWithTitle:[oldCategory capitalizedString]];

	if (item != nil)
		[mTheMenu removeItem:item];
}

- (void)renameCategoryWithInfo:(NSDictionary*)info
{
	NSString* oldCategory = [info objectForKey:@"old_name"];
	NSString* newName = [info objectForKey:@"new_name"];

	NSMenuItem* item = [mTheMenu itemWithTitle:[oldCategory capitalizedString]];

	if (item != nil) {
		[mTheMenu removeItem:item];
		[item setTitle:[newName capitalizedString]];

		// where should it be reinserted to maintain sorting?

		NSArray* temp = [mCatManagerRef allCategories];
		NSInteger indx = [temp indexOfObject:newName];

		if (mOptions & kDKIncludeAllItems)
			++indx; // +1 allows for hidden title item unless we skipped "All Items"

		if (mCategoriesOnly) {
			--indx; // we're off by 1 somewhere

			if (mOptions & kDKIncludeRecentlyUsedItems)
				++indx;

			if (mOptions & kDKIncludeRecentlyAddedItems)
				++indx;

			if ((mOptions & kDKDontAddDividingLine) == 0)
				++indx;
		}
		if (indx > [mTheMenu numberOfItems])
			indx = [mTheMenu numberOfItems];

		[mTheMenu insertItem:item
					 atIndex:indx];
	}
}

- (void)addKey:(NSString*)aKey
{
	if (mCategoriesOnly)
		return;

	LogEvent_(kInfoEvent, @"adding item key '%@' to menu %@", aKey, self);

	// the key may be being added to several categories, so first get a list of the categories that it belongs to

	NSArray* cats = [mCatManagerRef categoriesContainingKey:aKey];
	id repObject = [mCatManagerRef objectForKey:aKey];

	// iterate over the categories and find the menu responsible for it

	for (NSString* cat in cats) {
		NSMenuItem* catItem = [mTheMenu itemWithTitle:[cat capitalizedString]];

		if (catItem != nil) {
			NSMenu* subMenu = [catItem submenu];

			if (subMenu == nil) {
				// make a submenu to list the actual items

				subMenu = [self createSubmenuWithTitle:[cat capitalizedString]
											  forArray:@[aKey]];
				[catItem setSubmenu:subMenu];
				[catItem setEnabled:YES];
			} else {
				// check it's not present already - use the rep object

				NSInteger indx = [subMenu indexOfItemWithRepresentedObject:repObject];

				if (indx == -1) {
					// this menu needs to contain the item, so create an item to add to it. The title is initially set to the key
					// but the client may decide to change it.

					NSMenuItem* childItem = [[NSMenuItem alloc] initWithTitle:[aKey capitalizedString]
																	   action:mSelector
																keyEquivalent:@""];

					// call the callback to make this item into what its client needs

					[childItem setTarget:mTargetRef];
					[childItem setRepresentedObject:repObject];

					if (mCallbackTargetRef && [mCallbackTargetRef respondsToSelector:@selector(menuItem:wasAddedForObject:inCategory:)])
						[mCallbackTargetRef menuItem:childItem
								   wasAddedForObject:repObject
										  inCategory:cat];

					[childItem setTag:kDKCategoryManagerManagedMenuItemTag];

					// the client should have set its title to something readable, so use that to determine where it should be inserted

					NSString* title = [childItem title];
					NSArray* temp = [mCatManagerRef allSortedNamesInCategory:cat];
					NSInteger insertIndex = [temp indexOfObject:title];

					// not found here would be an error, but not a serious one...

					if (insertIndex == NSNotFound)
						insertIndex = 0;

					//NSLog(@"insertion index = %d in array: %@", insertIndex, temp );

					[subMenu insertItem:childItem
								atIndex:insertIndex];
				}
			}
		}
	}
}

- (void)addRecentlyAddedOrUsedKey:(NSString*)aKey
{
	// manages the menu for recently added and recently used items. When the key is added, it is added to the menu and any keys no longer
	// in the arrays are removed from the menu. If <aKey> is nil the menu will drop any items not in the original array.

	LogEvent_(kInfoEvent, @"synching recent menus for key '%@' for menu %@", aKey, self);

	NSInteger k;

	for (k = 0; k < 2; ++k) {
		NSArray* array;
		NSMenu* raSub;
		id repObject;

		if (k == 0) {
			array = [mCatManagerRef recentlyAddedItems];
			raSub = [mRecentlyAddedMenuItemRef submenu];

			[mRecentlyAddedMenuItemRef setEnabled:[array count] > 0];
		} else {
			array = [mCatManagerRef recentlyUsedItems];
			raSub = [mRecentlyUsedMenuItemRef submenu];

			[mRecentlyUsedMenuItemRef setEnabled:[array count] > 0];
		}

		if (!mCategoriesOnly && raSub != nil) {
			// remove any menu items that are not present in the array

			NSArray* items = [[raSub itemArray] copy];

			for (NSMenuItem* item in items) {
				NSArray* allKeys = [mCatManagerRef keysForObject:[item representedObject]];

				// if there are no keys, the object can't be known to the cat mgr, so delete it from the menu now

				if ([allKeys count] < 1)
					[raSub removeItem:item];
				else {
					// still known, but may not be listed in the array

					NSString* kk = [allKeys lastObject];

					if (kk != nil && ![array containsObject:kk])
						[raSub removeItem:item];
				}
			}

			// add a new item for the newly added key if it's unknown in the menu

			if (aKey != nil && [array containsObject:aKey]) {
				repObject = [mCatManagerRef objectForKey:aKey];
				NSInteger indx = [raSub indexOfItemWithRepresentedObject:repObject];

				if (indx == -1) {
					NSMenuItem* childItem = [[NSMenuItem alloc] initWithTitle:[aKey capitalizedString]
																	   action:mSelector
																keyEquivalent:@""];

					[childItem setRepresentedObject:repObject];
					[childItem setTarget:mTargetRef];

					if (mCallbackTargetRef && [mCallbackTargetRef respondsToSelector:@selector(menuItem:wasAddedForObject:inCategory:)])
						[mCallbackTargetRef menuItem:childItem
								   wasAddedForObject:repObject
										  inCategory:nil];

					// just added, so will always be first item in the list

					[childItem setTag:kDKCategoryManagerManagedMenuItemTag];
					[raSub insertItem:childItem
							  atIndex:0];
				}
			}
		}
	}
}

- (void)syncRecentlyUsedMenuForKey:(NSString*)aKey
{
	// the keyed item has moved to the front of the list - do the same for the associated menu item. This is the only
	// menu that requires this because all others can only have one object added or removed at a time, not moved within the same list.

	if (mCategoriesOnly)
		return;

	NSMenu* recentItemsMenu = [mRecentlyUsedMenuItemRef submenu];

	if (recentItemsMenu != nil) {
		id repObject = [mCatManagerRef objectForKey:aKey];
		NSInteger indx = [recentItemsMenu indexOfItemWithRepresentedObject:repObject];

		if (indx != -1) {
			NSMenuItem* item = [recentItemsMenu itemAtIndex:indx];
			[recentItemsMenu removeItem:item];
			[recentItemsMenu insertItem:item
								atIndex:0];
		}
	}
}

- (void)removeKey:(NSString*)aKey
{
	//NSLog(@"removing item key '%@' from menu %@", aKey, self );

	if (mCategoriesOnly)
		return;

	NSArray* cats = [mCatManagerRef categoriesContainingKey:aKey];
	id repObject = [mCatManagerRef objectForKey:aKey];

	// iterate over the categories and find the menu responsible for it

	for (NSString* cat in cats) {
		NSMenuItem* catItem = [mTheMenu itemWithTitle:[cat capitalizedString]];

		if (catItem != nil) {
			NSMenu* subMenu = [catItem submenu];

			if (subMenu != nil) {
				// this submenu contains the item, so delete the menu item that contains it. Because the item's
				// title may have been changed by the client, we use the represented object to discover the correct item.

				NSInteger indx = [subMenu indexOfItemWithRepresentedObject:repObject];

				if (indx != -1) {
					[subMenu removeItemAtIndex:indx];

					// if this leaves an entirely empty menu, delete it and disable the parent item

					if ([subMenu numberOfItems] == 0) {
						[catItem setSubmenu:nil];
						[catItem setEnabled:NO];
					}
				}
			}
		}
	}
}

- (void)checkItemsForKey:(NSString*)key
{
	// puts a checkmark against any category names in the menu that contain <key>.

	if (mCategoriesOnly)
		return;

	NSArray* categories = [mCatManagerRef categoriesContainingKey:key];

	// check whether there's really anything to do here:

	if ([categories count] > 1) {
		for (NSMenuItem* item in [mTheMenu itemArray]) {
			NSString* ti = [item title];

			if ([categories containsObject:ti])
				[item setState:NSOnState];
			else
				[item setState:NSOffState];
		}
	}
}

- (void)updateForKey:(NSString*)key
{
	// the object keyed by <key> has changed, so menu items pertaining to it need to be updated. The items involved are
	// not recreated or moved, they are simply passed to the client so that their titles, icons or whatever can be set
	// just as if the item was freshly created.

	if (mCategoriesOnly)
		return;

	NSAssert(key != nil, @"can't update - key was nil");
	LogEvent_(kInfoEvent, @"updating menu %@ for key '%@'", self, key);

	NSMutableArray* categories = [[mCatManagerRef categoriesContainingKey:key] mutableCopy];

	// add the recent items/added menus as if they were categories

	[categories addObject:NSLocalizedString(kDKRecentlyUsedUserString, @"")];
	[categories addObject:NSLocalizedString(kDKRecentlyAddedUserString, @"")];

	// check whether there's really anything to do here:

	id repObject = [mCatManagerRef objectForKey:key];

	for (NSString* catName in categories) {
		NSMenu* subMenu = [[mTheMenu itemWithTitle:[catName capitalizedString]] submenu];

		if (subMenu != nil) {
			NSInteger indx = [subMenu indexOfItemWithRepresentedObject:repObject];

			if (indx != -1) {
				NSMenuItem* item = [subMenu itemAtIndex:indx];

				// keep track of the title so that if it changes we can resort the menu

				NSString* oldTitle = [item title];

				if (mCallbackTargetRef && [mCallbackTargetRef respondsToSelector:@selector(menuItem:wasAddedForObject:inCategory:)])
					[mCallbackTargetRef menuItem:item
							   wasAddedForObject:repObject
									  inCategory:catName];

				// if title changed, reposition the item

				if (![oldTitle isEqualToString:[item title]]) {
					// where to insert?

					NSArray* names = [mCatManagerRef allSortedNamesInCategory:catName];
					indx = [names indexOfObject:[item title]];

					if (indx != NSNotFound) {
						[subMenu removeItem:item];
						[subMenu insertItem:item
									atIndex:indx];
					}
				}
			}
		}
	}
}

- (void)removeAll
{
	// removes all managed items and submenus from the menu excluding the recent items

	[self removeItemsInMenu:mTheMenu
					withTag:kDKCategoryManagerManagedMenuItemTag
			 excludingItem0:(mOptions & kDKMenuIsPopUpMenu) != 0];

	// empty the recent items menus also
	if (mRecentlyUsedMenuItemRef != nil) {
		[self removeItemsInMenu:[mRecentlyUsedMenuItemRef submenu]
						withTag:kDKCategoryManagerManagedMenuItemTag
				 excludingItem0:NO];
		[mRecentlyUsedMenuItemRef setEnabled:NO];
	}

	if (mRecentlyAddedMenuItemRef != nil) {
		[self removeItemsInMenu:[mRecentlyAddedMenuItemRef submenu]
						withTag:kDKCategoryManagerManagedMenuItemTag
				 excludingItem0:NO];
		[mRecentlyAddedMenuItemRef setEnabled:NO];
	}
}

- (void)createMenu
{
	mTheMenu = [[NSMenu alloc] initWithTitle:@"Category Manager"];

	NSArray* catObjects;
	NSMenuItem* parentItem;

	// don't use the menu item validation protocol - always enabled

	[mTheMenu setAutoenablesItems:NO];

	if ((mOptions & kDKMenuIsPopUpMenu) != 0) {
		// callback can check object == this to set the title of the popup (generally not needed - whoever called the CM
		// to make the menu in the first place is likely to be able to just set the menu or pop-up button's title afterwards).

		parentItem = [mTheMenu addItemWithTitle:@"Category Manager"
										 action:0
								  keyEquivalent:@""];

		if (mCallbackTargetRef && [mCallbackTargetRef respondsToSelector:@selector(menuItem:wasAddedForObject:inCategory:)])
			[mCallbackTargetRef menuItem:parentItem
					   wasAddedForObject:self
							  inCategory:nil];
	}

	for (NSString* cat in [mCatManagerRef allCategories]) {
		// if flagged to exclude "all items" then skip it

		if (((mOptions & kDKIncludeAllItems) == 0) && [cat isEqualToString:kDKDefaultCategoryName])
			continue;

		// always add a parent item for the category even if it turns out to be empty - this ensures that the menu UI
		// is consistent with other UI that may be just listing available categories.

		parentItem = [mTheMenu addItemWithTitle:[cat capitalizedString]
										 action:0
								  keyEquivalent:@""];
		[parentItem setTag:kDKCategoryManagerManagedMenuItemTag];

		// get the sorted list of items in the category

		catObjects = [mCatManagerRef allSortedKeysInCategory:cat];

		if ([catObjects count] > 0) {
			// make a submenu to list the actual items

			NSMenu* catMenu = [self createSubmenuWithTitle:[cat capitalizedString]
												  forArray:catObjects];
			[parentItem setSubmenu:catMenu];
			[parentItem setEnabled:YES];
		} else
			[parentItem setEnabled:NO];
	}

	// conditionally add "recently used" and "recently added" items

	if ((mOptions & (kDKIncludeRecentlyAddedItems | kDKIncludeRecentlyUsedItems)) != 0)
		[mTheMenu addItem:[NSMenuItem separatorItem]];

	NSString* title;
	NSMenu* subMenu;

	if ((mOptions & kDKIncludeRecentlyUsedItems) != 0) {
		title = NSLocalizedString(kDKRecentlyUsedUserString, @"");
		parentItem = [mTheMenu addItemWithTitle:title
										 action:0
								  keyEquivalent:@""];
		subMenu = [self createSubmenuWithTitle:title
									  forArray:[mCatManagerRef recentlyUsedItems]];

		[parentItem setTag:kDKCategoryManagerRecentMenuItemTag];
		[parentItem setSubmenu:subMenu];
		mRecentlyUsedMenuItemRef = parentItem;

		[mRecentlyUsedMenuItemRef setEnabled:[[mCatManagerRef recentlyUsedItems] count] > 0];
	}

	if ((mOptions & kDKIncludeRecentlyAddedItems) != 0) {
		title = NSLocalizedString(kDKRecentlyAddedUserString, @"");
		parentItem = [mTheMenu addItemWithTitle:title
										 action:0
								  keyEquivalent:@""];
		subMenu = [self createSubmenuWithTitle:title
									  forArray:[mCatManagerRef recentlyAddedItems]];

		[parentItem setTag:kDKCategoryManagerRecentMenuItemTag];
		[parentItem setSubmenu:subMenu];
		mRecentlyAddedMenuItemRef = parentItem;

		[mRecentlyAddedMenuItemRef setEnabled:[[mCatManagerRef recentlyAddedItems] count] > 0];
	}
}

- (void)createCategoriesMenu
{
	mTheMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Categories", @"default name for categories menu")];
	NSMenuItem* ti = nil;

	// add standard items according to options

	if (mOptions & kDKIncludeAllItems) {
		ti = [mTheMenu addItemWithTitle:kDKDefaultCategoryName
								 action:mSelector
						  keyEquivalent:@""];
		[ti setTarget:mTargetRef];
		[ti setTag:kDKCategoryManagerManagedMenuItemTag];
	}

	if (mOptions & kDKIncludeRecentlyAddedItems) {
		mRecentlyAddedMenuItemRef = [mTheMenu addItemWithTitle:kDKRecentlyAddedUserString
														action:mSelector
												 keyEquivalent:@""];
		[mRecentlyAddedMenuItemRef setTarget:mTargetRef];
		[mRecentlyAddedMenuItemRef setTag:kDKCategoryManagerRecentMenuItemTag];
	}

	if (mOptions & kDKIncludeRecentlyUsedItems) {
		mRecentlyUsedMenuItemRef = [mTheMenu addItemWithTitle:kDKRecentlyUsedUserString
													   action:mSelector
												keyEquivalent:@""];
		[mRecentlyUsedMenuItemRef setTarget:mTargetRef];
		[mRecentlyUsedMenuItemRef setTag:kDKCategoryManagerRecentMenuItemTag];
	}

	if ((mOptions & kDKDontAddDividingLine) == 0)
		[mTheMenu addItem:[NSMenuItem separatorItem]];

	// now just list the categories

	NSArray* allCats = [mCatManagerRef allCategories]; // already sorted alphabetically

	for (NSString* cat in allCats) {
		if (![cat isEqualToString:kDKDefaultCategoryName]) {
			ti = [mTheMenu addItemWithTitle:cat
									 action:mSelector
							  keyEquivalent:@""];
			[ti setTarget:mTargetRef];
			[ti setTag:kDKCategoryManagerManagedMenuItemTag];
			[ti setEnabled:YES];
		}
	}
}

- (NSMenu*)createSubmenuWithTitle:(NSString*)title forArray:(NSArray*)items
{
	// given an array of keys, this creates a menu listing the items. The delegate is called if present to finalise each item. The intended use for this
	// is to set up the "recently used" and "recently added" menus initially. If the array is empty returns an empty menu.

	NSAssert(items != nil, @"can't create menu for nil array");

	NSMenu* theMenu;

	theMenu = [[NSMenu alloc] initWithTitle:title];

	for (NSString* key in items) {
		NSMenuItem* childItem = [theMenu addItemWithTitle:[key capitalizedString]
												   action:mSelector
											keyEquivalent:@""];
		[childItem setTarget:mTargetRef];
		id repObject = [mCatManagerRef objectForKey:key];
		[childItem setRepresentedObject:repObject];

		if (mCallbackTargetRef && [mCallbackTargetRef respondsToSelector:@selector(menuItem:wasAddedForObject:inCategory:)])
			[mCallbackTargetRef menuItem:childItem
					   wasAddedForObject:repObject
							  inCategory:nil];

		[childItem setTag:kDKCategoryManagerManagedMenuItemTag];
	}

	return theMenu;
}

#pragma mark -

- (void)removeItemsInMenu:(NSMenu*)aMenu withTag:(NSInteger)tag excludingItem0:(BOOL)title
{
	NSMutableArray* items = [[aMenu itemArray] mutableCopy];

	NSLog(@"menu items = %@", items);

	// if a pop-up menu, don't remove the title item

	if (title)
		[items removeObjectAtIndex:0];

	NSEnumerator* iter = [items reverseObjectEnumerator];

	for (NSMenuItem* item in iter) {
		if ([item tag] == tag)
			[aMenu removeItem:item];
	}
}

@end
