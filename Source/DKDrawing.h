/**
 @author Contributions from the community; see CONTRIBUTORS.md
 @date 2005-2016
 @copyright MPL2; see LICENSE.txt
*/

#import "DKLayerGroup.h"

@class DKGridLayer, DKGuideLayer, DKKnob, DKViewController, DKImageDataManager, DKUndoManager;
@protocol DKDrawingDelegate;

typedef NSString* DKDrawingUnits NS_TYPED_EXTENSIBLE_ENUM;
typedef NSString* DKDrawingInfoKey NS_TYPED_EXTENSIBLE_ENUM;

NS_ASSUME_NONNULL_BEGIN

/** @brief A DKDrawing is the model data for the drawing system.

 Usually a document will own one of these. A drawing consists of one or more DKLayers,
 each of which contains any number of drawable objects, or implements some special feature such as a grid or guides, etc.

 A drawing can have multiple views, though typically it will have only one. Each view is managed by a single view controller, either an instance
 or subclass of DKViewController. Drawing updates refersh all views via their controllers, and input from the views is directed to the current
 active layer through the controller. The drawing owns the controllers, but the views are owned as normal by their respective superviews. The controller
 provides only weak references to both drawing and view to prevent potential retain cycles when a view owns a drawing for the automatic backend scenario.
 
 The drawing and the attached views must all have the same bounds size (though the views are free to have any desired frame). Setting the
 drawing size will adjust the views' bounds automatically.

 The active layer will receive mouse events from any of the attached views via its controller. (Because the user can't mouse in more than one view
 at a time, there is no contention here.) The commands will go to whichever view is the current responder and be passed on appropriately.

 Drawings can be saved simply by archiving them, thus all parts of the drawing need to adopt the NSCoding protocol.
*/
@interface DKDrawing : DKLayerGroup <NSCoding, NSCopying> {
@private
	DKDrawingUnits m_units; /**< user readable drawing units string, e.g. "millimetres" */
	DKLayer* __weak m_activeLayerRef; /**< which one is active for editing, etc */
	NSColor* m_paperColour; /**< underlying colour of the "paper" */
	DKUndoManager* m_undoManager; /**< undo manager to use for data changes */
	NSColorSpace* mColourSpace; /**< the colour space of the drawing as a whole (nil means use default) */
	NSSize m_size; /**< dimensions of the drawing */
	CGFloat m_leftMargin; /**< margins */
	CGFloat m_rightMargin;
	CGFloat m_topMargin;
	CGFloat m_bottomMargin;
	CGFloat m_unitConversionFactor; /**< how many pixels does 1 unit cover? */
	BOOL mFlipped; /**< YES if Y coordinates increase downwards, NO if they increase upwards */
	BOOL m_snapsToGrid; /**< YES if grid snapping enabled */
	BOOL m_snapsToGuides; /**< YES if guide snapping enabled */
	BOOL m_useQandDRendering; /**< if YES, renderers have the option to use a fast but low quality drawing method */
	BOOL m_isForcedHQUpdate; /**< YES while refreshing to HQ after a LQ series */
	BOOL m_qualityModEnabled; /**< YES if the quality modulation is enabled */
	BOOL mPaperColourIsPrinted; /**< YES if paper colour should be printed (default is NO) */
	NSTimer* m_renderQualityTimer; /**< a timer used to set up high or low quality rendering dynamically */
	NSTimeInterval m_lastRenderTime; /**< time the last render operation occurred */
	NSTimeInterval mTriggerPeriod; /**< the time interval to use to trigger low quality rendering */
	NSRect m_lastRectUpdated; /**< for refresh in HQ mode */
	NSMutableSet<DKViewController*>* mControllers; /**< the set of current controllers */
	DKImageDataManager* mImageManager; /**< internal object used to substantially improve efficiency of image archiving */
	id<DKDrawingDelegate> __weak mDelegateRef; /**< delegate, if any */
	id __weak mOwnerRef; /**< back pointer to document or view that owns this */
}

/** @brief Return the current version number of the framework
 
 Is a number formatted in 8-4-4 bit format representing the current version number
 */
@property (class, readonly) NSUInteger drawkitVersion;

/** @brief Return the current version number and release status as a preformatted string

 This is intended for occasional display, rather than testing for the framework version.
 @return A string, e.g. "1.0.b6"
 */
@property (class, readonly, copy) NSString* drawkitVersionString;

/** @brief Return the current release status of the framework
 @return A string, either "alpha", "beta", "release candidate" or nil (final).
 */
@property (class, readonly, copy, nullable) NSString* drawkitReleaseStatus;

/** @brief Constructs the default drawing system when the system isn't prebuilt "by hand"

 As a convenience for users of DrawKit, if you set up a \c DKDrawingView in IB, and do nothing else,
 you'll get a fully working, prebuilt drawing system behind that view. This can be very handy for all
 sorts of uses. However, it is more usual to build the system the other way around - start with a
 drawing object within a document (say) and attach views to it. This gives you the flexibility to
 do it either way. For automatic construction, this method is called to supply the drawing.
 @param aSize - the size of the drawing to create
 @return a fully constructed default drawing system
 */
+ (DKDrawing*)defaultDrawingWithSize:(NSSize)aSize;

/** @brief Creates a drawing from a lump of data
 @param drawingData data representing an archived drawing
 @return the unarchived drawing
 */
+ (nullable DKDrawing*)drawingWithData:(NSData*)drawingData;

/** @brief Return the default derachiving helper for deaerchiving a drawing

 This helper is a delegate of the dearchiver during dearchiving and translates older or obsolete
 classes into modern ones, etc. The default helper deals with older DrawKit classes, but can be
 replaced to provide the same functionality for application-specific classes.
 @return the dearchiving helper
 */
@property (class, retain, null_resettable) id dearchivingHelper;

/** @brief Returns a new drawing number by incrementing the current default seed value
 @return a new drawing number
 */
+ (NSUInteger)newDrawingNumber;

/** @brief Returns a dictionary containing some standard drawing info attributes

 This is usually called by the drawing object itself when built new. Usually you'll want to replace
 its contents with your own info. A DKDrawingInfoLayer can interpret some of the standard values and
 display them in its info box.
 @return a mutable dictionary of standard drawing info
 */
@property (class, readonly, copy) NSMutableDictionary<DKDrawingInfoKey, id>* defaultDrawingInfo NS_REFINED_FOR_SWIFT;

/** @brief Sets the abbreviation for the given drawing units string

 This allows special abbreviations to be set for units if desired. The setting writes to the user
 defaults so is persistent.
 @param abbrev the abbreviation for the unit
 @param fullString the full name of the drawing units
 */
+ (void)setAbbreviation:(NSString*)abbrev forDrawingUnits:(DKDrawingUnits)fullString;

/** @brief Returns the abbreviation for the given drawing units string
 @param fullString the full name of the drawing units
 @return a string - the abbreviated form
 */
+ (NSString*)abbreviationForDrawingUnits:(DKDrawingUnits)fullString;

/** @brief designated initializer */
- (instancetype)initWithSize:(NSSize)size;

// owner (document or view)

/** @brief Sets the "owner" of this drawing.

 The owner is usually either a document, a window controller or a drawing view. It is not required to
 be set at all, though some higher-level conveniences may depend on it.
 */
@property (weak, nullable) id owner;

/** @name basic drawing parameters
 *	@{ */

/** @brief the paper dimensions of the drawing.
 
 The paper size is the absolute limits of ths drawing dimensions. Usually margins are set within this.
 */
@property (nonatomic) NSSize drawingSize;
/** @brief Sets the drawing's paper size and margins to be equal to the sizes stored in a \c NSPrintInfo object.
 
 Can be used to synchronise a drawing size to the settings for a printer.
 @param printInfo An \c NSPrintInfo object, obtained from the printing system.
 */
- (void)setDrawingSizeWithPrintInfo:(NSPrintInfo*)printInfo;

/** @brief Sets the margins for the drawing.
 
 The margins inset the drawing area within the \c papersize set.
 @param l The left margin in Quartz units.
 @param t The top margin in Quartz units.
 @param r The right margin in Quartz units.
 @param b The bottom margin in Quartz units.
 */
- (void)setMarginsLeft:(CGFloat)l top:(CGFloat)t right:(CGFloat)r bottom:(CGFloat)b NS_SWIFT_NAME(setMargins(left:top:right:bottom:));

/** @brief Sets the margins from the margin values stored in a NSPrintInfo object
 
 \c SetDrawingSizeFromPrintInfo: will also call this for you
 @param printInfo a NSPrintInfo object, obtained from the printing system
 */
- (void)setMarginsWithPrintInfo:(NSPrintInfo*)printInfo;

/** @brief The width of the left margin.
 */
@property (readonly) CGFloat leftMargin;

/** @brief The width of the right margin.
 */
@property (readonly) CGFloat rightMargin;

/** @brief The width of the top margin.
 */
@property (readonly) CGFloat topMargin;

/** @brief The width of the bottom margin.
 */
@property (readonly) CGFloat bottomMargin;

/** @brief Returns the interior region of the drawing, within the margins
 @return a rectangle, the interior area of the drawing (paper size less margins)
 */
@property (readonly) NSRect interior;

/** @brief Constrains the point within the interior area of the drawing
 @param p a point structure
 @return a point, equal to p if p is within the interior, otherwise pinned to the nearest point within
 */
- (NSPoint)pinPointToInterior:(NSPoint)p;

/** @brief Sets whether the Y axis of the drawing is flipped
 
 Drawings are typically flipped, \c YES is the default. This affects the \c -isFlipped return from a
 DKDrawingView. WARNING: drawings with flip set to \c NO may have issues at present as some lower level
 code is currently assuming a flipped view.
 
 Is \c YES to have increase Y going down, \c NO for increasing Y going up.
 */
@property (nonatomic, getter=isFlipped) BOOL flipped;

/** @brief Sets the destination colour space for the whole drawing

 Colours set by styles and so forth are converted to this colourspace when rendering. A value of
 \c nil will use whatever is set in the colours used by the styles.
 */
@property (strong, nullable) NSColorSpace* colourSpace;

/**
 @}
 @name setting the rulers to the grid
 @{ */

/** @brief Sets the units and basic coordinate mapping factor
 @param units a string which is the drawing units of the drawing, e.g. "millimetres"
 @param conversionFactor how many Quartz points per basic unit?
 */
- (void)setDrawingUnits:(DKDrawingUnits)units unitToPointsConversionFactor:(CGFloat)conversionFactor;

/** @brief Returns the full name of the drawing's units
 @return a string
 */
@property (readonly, copy) DKDrawingUnits drawingUnits;

/** @brief Returns the abbreviation of the drawing's units
 
 For those it knows about, it does a lookup. For unknown units, it uses the first two characters
 and makes them lower case. The delegate can also elect to supply this string if it prefers.
 */
@property (readonly, copy) NSString* abbreviatedDrawingUnits;

/** @brief Returns the number of Quartz units per basic drawing unit
 @return the conversion value
 */
@property (readonly) CGFloat unitToPointsConversionFactor;

/** @brief Returns the number of Quartz units per basic drawing unit, as optionally determined by the delegate
 
 This allows the delegate to return a different value for special requirements. If the delegate does
 not respond, the normal conversion factor is returned. Note that DK currently doesn't use this
 internally but app-level code may do if it further overlays a coordinate mapping on top of the
 drawing's own.
 @return the conversion value
 */
@property (readonly) CGFloat effectiveUnitToPointsConversionFactor;

/** @brief Sets up the rulers for all attached views to a previously registered ruler state
 
 DKGridLayer registers rulers to match its grid using the drawingUnits string returned by
 this class as the registration key. If your drawing doesn't have a grid but does use the rulers,
 you need to register the ruler setup yourself somewhere.
 @param unitString the name of a previously registered ruler state
 */
- (void)synchronizeRulersWithUnits:(DKDrawingUnits)unitString;

/** @} */
/** @name setting the delegate */

/** @brief Sets the delegate.
 
 See header for possible delegate methods.
 */
@property (weak, nullable) id<DKDrawingDelegate> delegate;

/** @name the drawing's view controllers
 @{ */

/** @brief Return the current controllers the drawing owns.
 
 Controllers are in no particular order. The drawing object owns its controllers.
 */
@property (readonly, copy) NSSet<DKViewController*>* controllers;

/** @brief Add a controller to the drawing
 
 A controller is associated with a view, but must be added to the drawing to forge the connection
 between the drawing and its views. The drawing owns the controller. DKDrawingDocument and the
 automatic back-end set-up handle all of this for you - you only need this if you are building
 the DK system entirely by hand.
 @param aController the controller to add
 */
- (void)addController:(DKViewController*)aController;

/** @brief Removes a controller from the drawing
 
 Typically controllers are removed when necessary - there is little reason to call this yourself
 @param aController the controller to remove
 */
- (void)removeController:(DKViewController*)aController;

/** @brief Removes all controller from the drawing.

 Typically controllers are removed when necessary - there is little reason to call this yourself.
 */
- (void)removeAllControllers;

/** @}
 @name passing information to the views
 @{ */

/** @brief Causes all cursor rectangles for all attached views to be recalculated. This forces any cursors
 that may be in use to be updated.
 */
- (void)invalidateCursors;

/** @brief Causes all attached views to scroll to show the rect, if necessary
 
 Called for things like scroll to selection - all attached views may scroll if necessary. Note that
 it is OK to directly call the view's methods if scrolling a single view is required - the drawing
 isn't aware of any view's scroll position.
 @param rect the rect to reveal
 */
- (void)scrollToRect:(NSRect)rect;

/** @brief For the utility of contained objects, this ends any open text editing session without the object
 needing to know which view is handling it.
 
 If any attached view has started a temporary text editing mode, this method can be called to end
 that mode and perform all necessary cleanup. This is useful if the object that requested the mode
 no longer knows which view it asked to do the editing (and thus saves it the need to record the
 view in question). Note that normally only one such view could have entered this mode, but this
 will also recover from a situation (bug!) where more than one has a text editing operation mode open.
 */
- (void)exitTemporaryTextEditingMode;

/** @brief Notifies all the controllers that an object within the drawing notified a status change
 
 Status changes are non-visual changes that a view controller might want to know about
 @param object the original object that sent the notification
 */
- (void)objectDidNotifyStatusChange:(id)object;

/** @} */
/** @name dynamically adjusting the rendering quality:
 @{ */

/** @brief Set whether drawing quality modulation is enabled or not

 Rasterizers are able to use a low quality drawing mode for rapid updates when DKDrawing detects
 the need for it. This flag allows that behaviour to be turned on or off.
 */
@property BOOL dynamicQualityModulationEnabled;

/** @brief Advise whether drawing should be done in best quality or not
 
 Rasterizers in DK can query this flag to check if they can use a fast quick rendering method.
 this is set while zooming, scrolling or other operations that require many rapid updates. Speed
 under these conditions can be improved by using bitmap caches, etc rather than drawing at best
 quality.
 
 Set to \c YES to offer low quality faster rendering.
 */
@property BOOL lowRenderingQuality;

/** @brief Dynamically check if low or high quality should be used
 
 Called from the drawing method, this starts or extends a timer which will set high quality after
 a delay. Thus if rapid updates are happening, it will switch to low quality, and switch to high
 quality after a delay.
 */
- (void)checkIfLowQualityRequired;
- (void)qualityTimerCallback:(NSTimer*)timer;
@property NSTimeInterval lowQualityTriggerInterval;

/** @} */
/** @name setting the undo manager:
 @{ */

/** @brief The \c undoManager that will be used for all undo actions that occur in this drawing.
 
 The \c undoManager is retained. It is passed down to all levels that need undoable actions. The
 default is nil, so nothing will be undoable unless you set it. In a document-based app, the
 document's \c undoManager should be used. Otherwise, the view's or window's \c undoManager can be used.
 */
@property (nonatomic, strong, nullable) id undoManager;

/** @} */
/** @name drawing meta-data:
 @{ */

/** @brief The drawing info metadata of the drawing.
 
 The drawing info contains whatever you want, but a number of standard fields are defined and can be
 interpreted by a DKDrawingInfoLayer, if there is one. Note this inherits the storage from
 DKLayer.
 */
@property (copy, nullable) NSMutableDictionary<DKDrawingInfoKey, id>* drawingInfo NS_REFINED_FOR_SWIFT;

/** @name rendering the drawing:
 @{ */

/** @brief The current paper colour of the drawing.
 
 Default is white.
 @return the current colour of the background (paper).
 */
@property (nonatomic, strong, nullable) NSColor* paperColour;

/** @brief Whether the paper colour is printed or not.
 
 Default is \c NO
 */
@property BOOL paperColourIsPrinted;

/** @} */
/** @name active layer
 @{ */

/** @brief Sets which layer is currently active.
 
 The active layer is automatically linked from the first responder so it can receive commands
 active state changes.
 @param aLayer The layer to make the active layer, or \c nil to make no layer active.
 @return \c YES if the active layer changed, \c NO if not.
 */
- (BOOL)setActiveLayer:(nullable DKLayer*)aLayer;
/** @brief Sets which layer is currently active, optionally making this change undoable.
 
 Normally active layer changes are not undoable as the active layer is not considered part of the
 state of the data model. However some actions such as adding and removing layers should include
 the active layer state as part of the undo, so that the user experience is pleasant.
 @param aLayer The layer to make the active layer, or \c nil to make no layer active.
 @return \c YES if the active layer changed, \c NO if not.
 */
- (BOOL)setActiveLayer:(nullable DKLayer*)aLayer withUndo:(BOOL)undo;
/** @brief Returns the current active layer
 @return a DKLayer object, or subclass, which is the current active layer.
 */
@property (nonatomic, weak, readonly, nullable) DKLayer* activeLayer;
/** @brief Returns the active layer if it matches the requested class.
 @param aClass The class of layer sought.
 @return The active layer if it matches the requested class, otherwise \c nil
 */
- (nullable __kindof DKLayer*)activeLayerOfClass:(Class)aClass NS_REFINED_FOR_SWIFT;

/** @} */
/** @name high level methods that help support a UI
 @{ */

/** @brief Adds a layer to the drawing and optionally activates it
 
 This method has the advantage over separate add + activate calls that the active layer change is
 recorded by the undo stack, so it's the better one to use when adding layers via a UI since an
 undo of the action will restore the UI to its previous state with respect to the active layer.
 Normally changes to the active layer are not undoable.
 @param aLayer a layer object to be added
 @param activateIt if <code>YES</code>, the added layer will be made the active layer, \c NO will not change it.
 */
- (void)addLayer:(DKLayer*)aLayer andActivateIt:(BOOL)activateIt;

/** @brief Removes a layer from the drawing and optionally activates another one
 
 This method is the inverse of the one above, used to help make UIs more usable by also including
 undo for the active layer change. It is an error for \c anotherLayer to be equal to <code>aLayer</code>. As a
 further UI convenience, if \c aLayer is the current active layer, and \c anotherLayer is <code>nil</code>, this
 finds the topmost layer of the same class as \c aLayer and makes that active.
 @param aLayer A layer object to be removed.
 @param anotherLayer If not <code>nil</code>, this layer will be activated after removing the first one.
 */
- (void)removeLayer:(DKLayer*)aLayer andActivateLayer:(nullable DKLayer*)anotherLayer;

/** @brief Finds the first layer of the given class that can be activated.
 
 Looks through all subgroups.
 @param cl The class of layer to look for.
 @return The first such layer that returns \c YES to <code>-layerMayBecomeActive</code>.
 */
- (nullable __kindof DKLayer*)firstActivateableLayerOfClass:(Class)cl NS_REFINED_FOR_SWIFT;

/** @} */
/** @name interaction with grid and guides
 @{ */

/** @brief Whether mouse actions within the drawing should snap to grid or not.
 
 Actually snapping requires that objects call the \c snapToGrid: method for points that they are
 processing while dragging the mouse, etc.
 */
@property (nonatomic) BOOL snapsToGrid;

/** @brief Whether mouse actions within the drawing should snap to guides or not.
 
 Actually snapping requires that objects call the \c snapToGuides: method for points and rects that they are
 processing while dragging the mouse, etc.
 */
@property (nonatomic) BOOL snapsToGuides;

/** @brief Moves a point to the nearest grid position if snapControl is different from current user setting,
 otherwise returns it unchanged.
 
 The grid layer actually performs the computation, if one exists. The \c snapControl parameter
 usually comes from a modifer key such as control - if snapping is on it disables it, if off it
 enables it. This flag is passed up from whatever mouse event is actually being handled.
 @param p A point value within the drawing.
 @param snapControl Inverts the applied state of the grid snapping setting.
 @return A modified point located at the nearest grid intersection.
 */
- (NSPoint)snapToGrid:(NSPoint)p withControlFlag:(BOOL)snapControl;

/** @brief Moves a point to the nearest grid position if snap is turned ON, otherwise returns it unchanged
 
 The grid layer actually performs the computation, if one exists. If the control modifier key is down
 grid snapping is temporarily disabled, so this modifier universally means don't snap for all drags.
 Passing \c YES for \c ignore is intended for use by internal classes such as <code>DKGuideLayer</code>.
 @param p a point value within the drawing
 @param ignore If <code>YES</code>, the current state of <code>[self snapsToGrid]</code> is ignored.
 @return A modified point located at the nearest grid intersection.
 */
- (NSPoint)snapToGrid:(NSPoint)p ignoringUserSetting:(BOOL)ignore;

/** @brief Moves a point to a nearby guide position if snap is turned ON, otherwise returns it unchanged.
 
 The guide layer actually performs the computation, if one exists.
 @param p A point value within the drawing.
 @return A modified point located at a nearby guide.
 */
- (NSPoint)snapToGuides:(NSPoint)p;

/** @brief Snaps any edge (and optionally the centre) of a rect to any nearby guide.
 
 The guide layer itself implements the snapping calculations, if it exists.
 @param r A proposed rectangle which might be the bounds of some object for example.
 @param cent If YES, the centre point of the rect is also considered a candidadte for snapping, \c NO for
 just the edges.
 @return A rectangle, either the input rectangle or a rectangle of identical size offset to align with
 one of the guides.
 */
- (NSRect)snapRectToGuides:(NSRect)r includingCentres:(BOOL)cent;

/** @brief Determines the snap offset for any of a list of points.
 
 The guide layer itself implements the snapping calculations, if it exists.
 @param points an array containing NSValue objects with NSPoint values
 @return An offset amount which is the distance to move one of the points to make it snap. This value can
 usually be simply added to the current mouse point that is dragging the object.
 */
- (NSSize)snapPointsToGuide:(NSArray<NSValue*>*)points;

/** @brief Returns the amount meant by a single press of any of the arrow keys
 @discussion Is an x and y value representing how far each "nudge" should move an object. If there is a grid layer,
 and snapping is on, this will be a grid interval. Otherwise it will be <code>1</code>.
 */
@property (readonly) NSPoint nudgeOffset;

/** @brief Returns the master grid layer, if there is one
 
 Usually there will only be one grid, but if there is more than one this only finds the uppermost.
 This only returns a grid that returns YES to -isMasterGrid, so subclasses can return NO to
 prevent themselves being considered for this role.
 @return the grid layer, or nil
 */
@property (readonly, strong, nullable) DKGridLayer* gridLayer;

/** @brief Returns the guide layer, if there is one
 
 Usually there will only be one guide layer, but if there is more than one this only finds the uppermost.
 @return the guide layer, or nil
 */
@property (readonly, strong, nullable) DKGuideLayer* guideLayer;
- (CGFloat)convertLength:(CGFloat)len;
- (NSPoint)convertPoint:(NSPoint)pt;
- (NSPoint)convertPointFromDrawingToBase:(NSPoint)pt;
- (CGFloat)convertLengthFromDrawingToBase:(CGFloat)len;

/** @brief Convert a distance in quartz coordinates to the units established by the drawing grid

 This wraps up length conversion and formatting for display into one method, which also calls the
 delegate if it implements the relevant method.
 @param len a distance in base points (pixels)
 @return a string containing a fully formatted distance plus the units abbreviation
 */
- (NSString*)formattedConvertedLength:(CGFloat)len;

/** @brief Convert a point in quartz coordinates to the units established by the drawing grid

 This wraps up length conversion and formatting for display into one method, which also calls the
 delegate if it implements the relevant method. The result is an array with two strings - the first
 is the x coordinate, the second is the y co-ordinate
 @param pt a point in base points (pixels)
 @return a pair of strings containing a fully formatted distance plus the units abbreviation
 */
- (NSArray<NSString*>*)formattedConvertedPoint:(NSPoint)pt;

/** @} */
/** @name export
 @{ */

/** @brief Called just prior to an operation that saves the drawing to a file, pasteboard or data.
 
 Can be overridden or you can make use of the notification
 */
- (void)finalizePriorToSaving;
/** @brief Saves the entire drawing to a file
 
 Implies the binary format
 @param filename the full path of the file
 @param atom \c YES to save to a temporary file and swap (safest), \c NO to overwrite file
 @return \c YES if succesfully written, \c NO otherwise
 */
- (BOOL)writeToFile:(NSString*)filename atomically:(BOOL)atom;

/** @brief Saves the entire drawing to a file URL.
 
 Implies the binary format.
 @param url the full file URL of the file.
 @param writeOptionsMask see \c NSDataWritingOptions for more info.
 @param errorPtr If there is an error writing out the data, upon return contains an error
 object that describes the problem.
 @return \c YES if succesfully written, \c NO otherwise.
 */
- (BOOL)writeToURL:(NSURL*)url options:(NSDataWritingOptions)writeOptionsMask error:(NSError* _Nullable __autoreleasing* _Nullable)errorPtr;
- (NSData*)drawingAsXMLDataAtRoot;
- (NSData*)drawingAsXMLDataForKey:(NSString*)key;
- (NSData*)drawingData;
- (NSData*)pdf;

/** @} */
/** @name image manager
 @{ */

/** @brief Returns the image manager

 The image manager is an object that is used to improve archiving efficiency of images. Classes
 that have images, such as DKImageShape, use this to cache image data.
 @return the drawing's image manager
 */
@property (readonly, strong) DKImageDataManager* imageManager;

/** @} */
@end

/** @name notifications
 @memberof DKDrawing
 @{ */

extern NSNotificationName const kDKDrawingActiveLayerWillChange;
extern NSNotificationName const kDKDrawingActiveLayerDidChange;
extern NSNotificationName const kDKDrawingWillChangeSize;
extern NSNotificationName const kDKDrawingDidChangeSize;
extern NSNotificationName const kDKDrawingUnitsWillChange;
extern NSNotificationName const kDKDrawingUnitsDidChange;
extern NSNotificationName const kDKDrawingWillChangeMargins;
extern NSNotificationName const kDKDrawingDidChangeMargins;
extern NSNotificationName const kDKDrawingWillBeSavedOrExported;

/** @}
 @name keys for standard drawing info items:
 @memberof DKDrawing
 @{ */

extern NSString* const kDKDrawingInfoUserInfoKey; /**< the key for the drawing info dictionary within the user info */

extern DKDrawingInfoKey const kDKDrawingInfoDrawingNumber; /**< data type NSString */
extern DKDrawingInfoKey const kDKDrawingInfoDrawingNumberUnformatted; /**< data type NSNumber (integer) */
extern DKDrawingInfoKey const kDKDrawingInfoDrawingRevision; /**< data type NSNumber (integer) */
extern DKDrawingInfoKey const kDKDrawingInfoDrawingPrefix; /**< data type NSString */
extern DKDrawingInfoKey const kDKDrawingInfoDraughter; /**< data type NSString */
extern DKDrawingInfoKey const kDKDrawingInfoCreationDate; /**< data type NSDate */
extern DKDrawingInfoKey const kDKDrawingInfoLastModificationDate; /**< data type NSDate */
extern DKDrawingInfoKey const kDKDrawingInfoModificationHistory; /**< data type NSArray */
extern DKDrawingInfoKey const kDKDrawingInfoOriginalFilename; /**< data type NSString */
extern DKDrawingInfoKey const kDKDrawingInfoTitle; /**< data type NSString */
extern DKDrawingInfoKey const kDKDrawingInfoDrawingDimensions; /**< data type NSSize */
extern DKDrawingInfoKey const kDKDrawingInfoDimensionsUnits; /**< data type NSString */
extern DKDrawingInfoKey const kDKDrawingInfoDimensionsShortUnits; /**< data type NSString */

/** @}
 @brief keys for user defaults items
 @{ */
extern NSString* const kDKDrawingSnapToGridUserDefault; /**< BOOL */
extern NSString* const kDKDrawingSnapToGuidesUserDefault; /**< BOOL */
extern NSString* const kDKDrawingUnitAbbreviationsUserDefault; /**< NSDictionary */

/** @} */

/** @brief Delegate methods */
@protocol DKDrawingDelegate <NSObject>
@optional

- (void)drawing:(DKDrawing*)drawing willDrawRect:(NSRect)rect inView:(DKDrawingView*)aView;
- (void)drawing:(DKDrawing*)drawing didDrawRect:(NSRect)rect inView:(DKDrawingView*)aView;
- (NSPoint)drawing:(DKDrawing*)drawing convertLocationToExternalCoordinates:(NSPoint)drawingPt;
- (CGFloat)drawing:(DKDrawing*)drawing convertDistanceToExternalCoordinates:(CGFloat)drawingDistance;
- (NSString*)drawing:(DKDrawing*)drawing willReturnAbbreviationForUnit:(DKDrawingUnits)unit;
- (NSString*)drawing:(DKDrawing*)drawing willReturnFormattedCoordinateForDistance:(CGFloat)drawingDistance;
- (CGFloat)drawingWillReturnUnitToPointsConversonFactor:(DKDrawing*)drawing;

@end

/** @brief additional methods
*/
@interface DKDrawing (UISupport)

- (nullable NSWindow*)windowForSheet;

@end

/** @brief deprecated methods
 */
@interface DKDrawing (Deprecated)

+ (null_unspecified DKDrawing*)drawingWithContentsOfFile:(null_unspecified NSString*)filepath DEPRECATED_ATTRIBUTE;
+ (null_unspecified DKDrawing*)drawingWithData:(null_unspecified NSData*)drawingData fromFileAtPath:(null_unspecified NSString*)filepath DEPRECATED_ATTRIBUTE;

/** @brief Saves the static class defaults for ALL classes in the drawing system

 Deprecated - no longer does anything
 @deprecated no longer does anything
 */
+ (void)saveDefaults DEPRECATED_ATTRIBUTE;

/** @brief Loads the static user defaults for all classes in the drawing system

 Deprecated - no longer does anything
 @deprecated no longer does anything
 */
+ (void)loadDefaults DEPRECATED_ATTRIBUTE;

@end

extern DKDrawingUnits const DKDrawingUnitsInches;
extern DKDrawingUnits const DKDrawingUnitsMillimetres;
extern DKDrawingUnits const DKDrawingUnitsCentimetres;
extern DKDrawingUnits const DKDrawingUnitsMetres;
extern DKDrawingUnits const DKDrawingUnitsKilometres;
extern DKDrawingUnits const DKDrawingUnitsPicas;
extern DKDrawingUnits const DKDrawingUnitsPixels;
extern DKDrawingUnits const DKDrawingUnitsFeet;
extern DKDrawingUnits const DKDrawingUnitsYards;
extern DKDrawingUnits const DKDrawingUnitsPoints;
extern DKDrawingUnits const DKDrawingUnitsMiles;

NS_ASSUME_NONNULL_END
