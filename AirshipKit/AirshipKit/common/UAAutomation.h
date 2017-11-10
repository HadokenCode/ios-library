/* Copyright 2017 Urban Airship and Contributors */

#import <Foundation/Foundation.h>
#import "UASchedule.h"
#import "UAActionScheduleInfo.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Automation schedules limit.
 */
extern NSUInteger const UAAutomationScheduleLimit;

/**
 * Manager class for scheduling actions.
 */
@interface UAAutomation : NSObject

///---------------------------------------------------------------------------------------
/// @name Automation Schedule Management Methods
///---------------------------------------------------------------------------------------

/**
 * Schedules actions.
 *
 * @param scheduleInfo The schedule information.
 * @param completionHandler The completion handler when the action is scheduled.
 * If the schedule info is invalid, the action schedule will be nil.
 */
- (void)scheduleActions:(UAActionScheduleInfo *)scheduleInfo
      completionHandler:(nullable void (^)(UASchedule * __nullable))completionHandler;

/**
 * Cancels a schedule with the given identifier.
 *
 * @param identifier A schedule identifier.
 */
- (void)cancelScheduleWithIdentifier:(NSString *)identifier;

/**
 * Cancels all schedules of the given group.
 *
 * @param group A schedule group.
 */
- (void)cancelSchedulesWithGroup:(NSString *)group;

/**
 * Cancels all schedules.
 */
- (void)cancelAll;

/**
 * Gets the schedule with the given identifier.
 *
 * @param identifier A schedule identifier.
 * @param completionHandler The completion handler with the result.
 */
- (void)getScheduleWithIdentifier:(NSString *)identifier
                completionHandler:(void (^)(UASchedule * __nullable))completionHandler;

/**
 * Gets all schedules.
 *
 * @param completionHandler The completion handler with the result.
 */
- (void)getSchedules:(void (^)(NSArray<UASchedule *> *))completionHandler;

/**
 * Gets all schedules of the given group.
 *
 * @param group The schedule group.
 * @param completionHandler The completion handler with the result.
 */
- (void)getSchedulesWithGroup:(NSString *)group
            completionHandler:(void (^)(NSArray<UASchedule *> *))completionHandler;

@end

NS_ASSUME_NONNULL_END