//
//  PasswordController.swift
//  MyMonero
//
//  Created by Paul Shapiro on 5/22/17.
//  Copyright © 2017 MyMonero. All rights reserved.
//

import Foundation
import RNCryptor
//
protocol DeleteEverythingRegistrant
{
//	func …()
}
protocol PasswordEntryDelegate
{
	func getUserToEnterExistingPassword(
		isForChangePassword: Bool,
		_ fn: @escaping (
			_ didCancel_orNil: Bool?,
			_ obtainedPasswordString: PasswordController.Password?
		) -> Void
	)
	func getUserToEnterNewPasswordAndType(
		isForChangePassword: Bool,
		_ fn: @escaping (
			_ didCancel_orNil: Bool?,
			_ obtainedPasswordString: PasswordController.Password?,
			_ passwordType: PasswordController.PasswordType?
		) -> Void
	)
}
//
final class PasswordController
{
	// Types/Constants
	typealias Password = String
	enum PasswordType: String
	{
		case PIN = "PIN" // 6-digit numerical PIN/code
		case password = "password" // free-form, string password
		var lengthOfPIN: Int { return 6 }
		var humanReadableString: String
		{
			return self.rawValue
		}
		var capitalized_humanReadableString: String
		{
			return self.humanReadableString.capitalized
		}
		func new(detectedFromPassword password: Password) -> PasswordType
		{
			let characters = password.characters
			if characters.count == lengthOfPIN { // if is 6 chars…
				let numbers: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
				if Set(characters).isSubset(of: numbers) { // and contains only numbers
					return .PIN
				}
			}
			return .password
		}
	}
	let collectionName = "PasswordMeta"
	let plaintextMessageToSaveForUnlockChallenges = "this is just a string that we'll use for checking whether a given password can unlock an encrypted version of this very message"
	enum DictKeys: String
	{
		case _id = "_id"
		case passwordType = "passwordType"
		case messageAsEncryptedDataForUnlockChallenge_base64String = "messageAsEncryptedDataForUnlockChallenge_base64String"
	}
	enum NotificationNames: String
	{
		case setFirstPasswordDuringThisRuntime = "PasswordController_NotificationNames_SetFirstPasswordDuringThisRuntime"
		case changedPassword = "PasswordController_NotificationNames_ChangedPassword"
		//
		case obtainedNewPassword = "PasswordController_Runtime_NotificationNames_ObtainedNewPassword"
		case obtainedCorrectExistingPassword = "PasswordController_Runtime_NotificationNames_ObtainedCorrectExistingPassword"
		//
		case erroredWhileSettingNewPassword = "PasswordController_Runtime_NotificationNames_ErroredWhileSettingNewPassword"
		case erroredWhileGettingExistingPassword = "PasswordController_Runtime_NotificationNames_ErroredWhileGettingExistingPassword"
		case canceledWhileEnteringExistingPassword = "PasswordController_Runtime_NotificationNames_canceledWhileEnteringExistingPassword"
		case canceledWhileEnteringNewPassword = "PasswordController_Runtime_NotificationNames_canceledWhileEnteringNewPassword"
		//
		case canceledWhileChangingPassword = "PasswordController_Runtime_NotificationNames_canceledWhileChangingPassword"
		case errorWhileChangingPassword = "PasswordController_Runtime_NotificationNames_errorWhileChangingPassword"
		//
		case willDeconstructBootedStateAndClearPassword = "PasswordController_Runtime_NotificationNames_willDeconstructBootedStateAndClearPassword"
		case didDeconstructBootedStateAndClearPassword = "PasswordController_Runtime_NotificationNames_didDeconstructBootedStateAndClearPassword"
		case havingDeletedEverything_didDeconstructBootedStateAndClearPassword = "PasswordController_Runtime_NotificationNames_havingDeletedEverything_didDeconstructBootedStateAndClearPassword"
		//
		var notificationName: NSNotification.Name { return NSNotification.Name(self.rawValue) }
	}
	enum Notification_UserInfo_Keys: String
	{
		case err_str = "err_str"
	}
	//
	// Properties
	var hasBooted = false
	var _id: DocumentPersister.DocumentId?
	var password: Password?
	var passwordType: PasswordType! // it will default to .password per init
	var hasUserSavedAPassword: Bool!
	var messageAsEncryptedDataForUnlockChallenge_base64String: String?
	var isAlreadyGettingExistingOrNewPWFromUser: Bool?
	var passwordEntryDelegate: PasswordEntryDelegate! // someone in the app must set this
	//
	// Lifecycle - Singleton Init
	static let shared = PasswordController()
	private init()
	{
		self.setup()
	}
	func setup()
	{
		self.startObserving_userIdle()
		self.initializeRuntimeAndBoot()
	}
	func startObserving_userIdle()
	{
		// TODO:
//		controller.on(
//			controller.EventName_userDidBecomeIdle(),
//			
//				{
//					if (self.hasUserSavedAPassword !== true) {
//						// nothing to do here because the app is not unlocked and/or has no data which would be locked
//						NSLog("💬  User became idle but no password has ever been entered/no saved data should exist.")
//						return
//					} else if (self.HasUserEnteredValidPasswordYet() !== true) {
//						// user has saved data but hasn't unlocked the app yet
//						NSLog("💬  User became idle and saved data/pw exists, but user hasn't unlocked app yet.")
//						return
//					}
//					self._didBecomeIdleAfterHavingPreviouslyEnteredPassword()
//			}
//		)
	}
	func initializeRuntimeAndBoot()
	{
		assert(self.hasBooted == false, "\(#function) called while already booted")
		let (err_str, documentJSONs) = DocumentPersister.shared().AllDocuments(
			inCollectionNamed: self.collectionName
		)
		if err_str != nil {
			NSLog("Fatal error while loading \(self.collectionName): \(err_str!)")
			// TODO: throw/crash?
			return
		}
		let documentJSONs_count = documentJSONs!.count
		if documentJSONs_count >= 1 {
			NSLog("Unexpected state while loading \(self.collectionName): more than one saved doc.")
			// TODO: throw/crash?
			return
		}
		func _proceedTo_load(
			hasUserSavedAPassword: Bool,
			documentJSON: DocumentPersister.DocumentJSON
		)
		{
			self.hasUserSavedAPassword = hasUserSavedAPassword
			//
			self._id = documentJSON[DictKeys._id.rawValue] as? DocumentPersister.DocumentId
			let passwordType_rawValue = documentJSON[DictKeys.passwordType.rawValue] as? String ?? PasswordType.password.rawValue
			self.passwordType = PasswordType(rawValue: passwordType_rawValue)
			self.messageAsEncryptedDataForUnlockChallenge_base64String = documentJSON[DictKeys.messageAsEncryptedDataForUnlockChallenge_base64String.rawValue] as? String
			if self._id != nil { // existing doc
				if self.messageAsEncryptedDataForUnlockChallenge_base64String == nil || self.messageAsEncryptedDataForUnlockChallenge_base64String == "" {
					// ^-- but it was saved w/o an encrypted challenge str
					// TODO: not sure how to handle this case. delete all local info? would suck
					let err_str = "Found undefined encrypted msg for unlock challenge in saved password model document"
					NSLog("Error: \(err_str)")
					return
				}
			}
			//
			self.hasBooted = true
			self._callAndFlushAllBlocksWaitingForBootToExecute()
			NSLog("✅  Booted \(self) and called all waiting blocks. Waiting for unlock.")
		}
		if documentJSONs_count == 0 {
			let fabricated_documentJSON =
			[
				DictKeys.passwordType.rawValue: PasswordType.password // default (at least for now)
			]
			_proceedTo_load(
				hasUserSavedAPassword: false,
				documentJSON: fabricated_documentJSON
			)
			return
		}
		let documentJSON = documentJSONs![0]
		_proceedTo_load(
			hasUserSavedAPassword: true,
			documentJSON: documentJSON
		)
	}
	//
	// Accessors - Runtime - Derived properties
	var hasUserEnteredValidPasswordYet: Bool
	{
		return self.password != nil
	}
	var isUserChangingPassword: Bool
	{
		return self.hasUserEnteredValidPasswordYet == true && self.isAlreadyGettingExistingOrNewPWFromUser == true
	}
	var new_incorrectPasswordValidationErrorMessageString: String
	{
		let humanReadable_passwordType = self.passwordType!.humanReadableString
		//
		return "Incorrect \(humanReadable_passwordType)"
	}
	//
	// Accessors - Deferring execution convenience methods
	func OnceBootedAndPasswordObtained(
		_ fn: @escaping (_ password: Password, _ passwordType: PasswordType) -> Void,
		_ userCanceled_fn: (() -> Void)? = {}
	)
	{
		func callBackHavingObtainedPassword()
		{
			fn(self.password!, self.passwordType)
		}
		func callBackHavingCanceled()
		{
			userCanceled_fn!()
		}
		if self.hasUserEnteredValidPasswordYet == true {
			callBackHavingObtainedPassword()
			return
		}
		// then we have to wait for it
		var hasCalledBack = false
		var token__obtainedNewPassword: Any?
		var token__obtainedCorrectExistingPassword: Any?
		var token__canceledWhileEnteringExistingPassword: Any?
		var token__canceledWhileEnteringNewPassword: Any?
		func ___guardAllCallBacks() -> Bool
		{
			if hasCalledBack == true {
				NSLog("PasswordController/OnceBootedAndPasswordObtained hasCalledBack already true")
				return false // ^- shouldn't happen but just in case…
			}
			hasCalledBack = true
			return true
		}
		func __stopListening()
		{
			NotificationCenter.default.removeObserver(token__obtainedNewPassword!)
			NotificationCenter.default.removeObserver(token__obtainedCorrectExistingPassword!)
			NotificationCenter.default.removeObserver(token__canceledWhileEnteringExistingPassword!)
			NotificationCenter.default.removeObserver(token__canceledWhileEnteringNewPassword!)
			token__obtainedNewPassword = nil
			token__obtainedCorrectExistingPassword = nil
			token__canceledWhileEnteringExistingPassword = nil
			token__canceledWhileEnteringNewPassword = nil
		}
		func _aPasswordWasObtained()
		{
			if (___guardAllCallBacks() != false) {
				__stopListening() // immediately unsubscribe
				callBackHavingObtainedPassword()
			}
		}
		func _obtainingPasswordWasCanceled()
		{
			if (___guardAllCallBacks() != false) {
				__stopListening() // immediately unsubscribe
				callBackHavingCanceled()
			}
		}
		self.onceBooted({ [unowned self] in
			// hang onto tokens so we can unsub
			token__obtainedNewPassword = NotificationCenter.default.addObserver(
				forName: NotificationNames.obtainedNewPassword.notificationName,
				object: self,
				queue: OperationQueue.main,
				using:
				{ (notification) in
					_aPasswordWasObtained()
				}
			)
			token__obtainedCorrectExistingPassword = NotificationCenter.default.addObserver(
				forName: NotificationNames.obtainedCorrectExistingPassword.notificationName,
				object: self,
				queue: OperationQueue.main,
				using:
				{ (notification) in
					_aPasswordWasObtained()
				}
			)
			token__canceledWhileEnteringExistingPassword = NotificationCenter.default.addObserver(
				forName: NotificationNames.canceledWhileEnteringExistingPassword.notificationName,
				object: self,
				queue: OperationQueue.main,
				using:
				{ (notification) in
					_obtainingPasswordWasCanceled()
				}
			)
			token__canceledWhileEnteringNewPassword = NotificationCenter.default.addObserver(
				forName: NotificationNames.canceledWhileEnteringNewPassword.notificationName,
				object: self,
				queue: OperationQueue.main,
				using:
				{ (notification) in
					_obtainingPasswordWasCanceled()
				}
			)
			// now that we're subscribed, initiate the pw request
			self.givenBooted_initiateGetNewOrExistingPasswordFromUserAndEmitIt()
		})
	}
	func givenBooted_initiateGetNewOrExistingPasswordFromUserAndEmitIt()
	{
		if self.hasUserEnteredValidPasswordYet == true {
			NSLog("Warn: \(#function) asked to givenBooted_initiateGetNewOrExistingPasswordFromUserAndEmitIt but already has password.")
			return // already got it
		}
		do { // guard
			if self.isAlreadyGettingExistingOrNewPWFromUser == true {
				return // only need to wait for it to be obtained
			}
			self.isAlreadyGettingExistingOrNewPWFromUser = true
		}
		// we'll use this in a couple places
		let isForChangePassword = false // this is simply for requesting to have the existing or a new password from the user
		//
		if self._id == nil { // if the user is not unlocking an already pw-protected app
			// then we need to get a new PW from the user
			self.obtainNewPasswordFromUser( // this will also call self.unguard_getNewOrExistingPassword()
				isForChangePassword: isForChangePassword
			)
			return
		} else { // then we need to get the existing PW and check it against the encrypted message
			//
			if self.messageAsEncryptedDataForUnlockChallenge_base64String == nil {
				let err_str = "Code fault: Existing document but no messageAsEncryptedDataForUnlockChallenge_base64String"
				NSLog("Error: \(err_str)")
				self.unguard_getNewOrExistingPassword()
				assert(false, err_str)
				return
			}
			self._getUserToEnterTheirExistingPassword(isForChangePassword: isForChangePassword)
			{ (didCancel_orNil, validationErr_orNil, obtainedPasswordString) in
				if validationErr_orNil != nil { // takes precedence over cancel
					self.unguard_getNewOrExistingPassword()
					NotificationCenter.default.post(
						name: NotificationNames.erroredWhileGettingExistingPassword.notificationName,
						object: self,
						userInfo: [ Notification_UserInfo_Keys.err_str.rawValue: validationErr_orNil! ]
					)
					return
				}
				if didCancel_orNil == true {
					NotificationCenter.default.post(
						name: NotificationNames.canceledWhileEnteringExistingPassword.notificationName,
						object: self
					)
					self.unguard_getNewOrExistingPassword()
					return // just silently exit after unguarding
				}
				
				let encrypted_data = self.messageAsEncryptedDataForUnlockChallenge_base64String!.data(using: .utf8)!
				var plaintext_data: Data?
				do {
					plaintext_data = try RNCryptor.decrypt(
						data: encrypted_data,
						withPassword: obtainedPasswordString!
					)
				} catch let e {
					self.unguard_getNewOrExistingPassword()
					NSLog("Error while decrypting message for unlock challenge: \(e.localizedDescription)")
					let err_str = self.new_incorrectPasswordValidationErrorMessageString
					NotificationCenter.default.post(
						name: NotificationNames.erroredWhileGettingExistingPassword.notificationName,
						object: self,
						userInfo: [ Notification_UserInfo_Keys.err_str.rawValue: err_str ]
					)
					return
				}
				let decryptedMessageForUnlockChallenge = String(data: plaintext_data!, encoding: .utf8)
				if decryptedMessageForUnlockChallenge != self.plaintextMessageToSaveForUnlockChallenges {
					self.unguard_getNewOrExistingPassword()
					let err_str = self.new_incorrectPasswordValidationErrorMessageString
					NotificationCenter.default.post(
						name: NotificationNames.erroredWhileGettingExistingPassword.notificationName,
						object: self,
						userInfo: [ Notification_UserInfo_Keys.err_str.rawValue: err_str ]
					)
					return
				}
				// then it's correct
				// hang onto pw and set state
				self._didObtainPassword(password: obtainedPasswordString!)
				// all done
				self.unguard_getNewOrExistingPassword()
				NotificationCenter.default.post(
					name: NotificationNames.obtainedCorrectExistingPassword.notificationName,
					object: self
				)
			}
		}
	}
	//
	//
	// Runtime - Imperatives - Private - Requesting password from user
	//
	func unguard_getNewOrExistingPassword()
	{
		self.isAlreadyGettingExistingOrNewPWFromUser = false
	}
	func _getUserToEnterTheirExistingPassword(
		isForChangePassword: Bool,
		_ fn: @escaping (
			_ didCancel_orNil: Bool?,
			_ validationErr_orNil: String?,
			_ obtainedPasswordString: Password?
		) -> Void
	)
	{
		var _passwordEntry_isCurrentlyLockedOut: Bool? = false
		var _passwordEntry_unlock_timer: Timer?
		var _numberOfTriesDuringThisTimePeriod: Int? = 0
		var _dateOf_firstPWTryDuringThisTimePeriod: Date? = Date()
//		func __cancelAnyAndRebuild_unlock_timeout()
//		{
//			const wasAlreadyLockedOut = unlock_timeout !== null
//			if (unlock_timeout !== null) {
//				// NSLog("💬  clearing existing unlock timer")
//				clearTimeout(unlock_timeout)
//				unlock_timeout = null // not strictly necessary
//			}
//			const unlockInT_s = 10 // allows them to try again every 20 s, but resets timer if they submit w/o waiting
//			NSLog(`🚫 Too many password entry attempts within ${unlockInT_s}s. ${!wasAlreadyLockedOut ? "Locking out" : "Extending lockout." }.`)
//			unlock_timeout = setTimeout(func()
//			{
//				NSLog("⭕️  Unlocking password entry.")
//				isCurrentlyLockedOut = false
//				self.__convenience_callWaitingCB_existingPassword(null, "", null) // this is _sort_ of a hack and should be made more explicit in API but I'm sending an empty string, and not even an Error, to clear the validation error so the user knows to try again
//			}, unlockInT_s * 1000)
//		}
		// Now put request out
		self.passwordEntryDelegate.getUserToEnterExistingPassword(isForChangePassword: isForChangePassword)
		{ (didCancel_orNil, obtainedPasswordString) in
			var validationErr_orNil: String? = nil // so far…
			if didCancel_orNil != true { // so user did NOT cancel
//				// user did not cancel… let's check if we need to send back a pre-emptive validation err (such as because they're trying too much)
//				if self._passwordEntry_isCurrentlyLockedOut == false {
//					if self._numberOfTriesDuringThisTimePeriod == 0 {
//						self._dateOf_firstPWTryDuringThisTimePeriod = Date()
//					}
//					numberOfTriesDuringThisTimePeriod += 1
//					let maxLegal_numberOfTriesDuringThisTimePeriod = 5
//					if (numberOfTriesDuringThisTimePeriod > maxLegal_numberOfTriesDuringThisTimePeriod) { // rhs must be > 0
//						numberOfTriesDuringThisTimePeriod = 0
//						// ^- no matter what, we're going to need to reset the above state for the next 'time period'
//						//
//						const now = new Date()
//						const ms_dateRange = now.getTime() - dateOf_firstPWTryDuringThisTimePeriod.getTime()
//						const ms_since_firstPWTryDuringThisTimePeriod = Math.abs(ms_dateRange)
//						const s_since_firstPWTryDuringThisTimePeriod = ms_since_firstPWTryDuringThisTimePeriod / 1000
//						const noMoreThanNTriesWithin_s = 30
//						if (s_since_firstPWTryDuringThisTimePeriod > noMoreThanNTriesWithin_s) { // enough time has passed since this group began - only reset the "time period" with tries->0 and let this pass through as valid check
//							dateOf_firstPWTryDuringThisTimePeriod = null // not strictly necessary to do here as we reset the number of tries during this time period to zero just above
//							NSLog(`There were more than ${maxLegal_numberOfTriesDuringThisTimePeriod} password entry attempts during this time period but the last attempt was more than ${noMoreThanNTriesWithin_s}s ago, so letting this go.`)
//						} else { // simply too many tries!…
//							// lock it out for the next time (supposing this try does not pass)
//							isCurrentlyLockedOut = true
//						}
//					}
//				}
//				if (isCurrentlyLockedOut == true) { // do not try to check pw - return as validation err
//					NSLog("🚫  Received password entry attempt but currently locked out.")
//					validationErr_orNil = new Error("As a security precaution, please wait a few moments before trying again.")
//					// setup or extend unlock timer - NOTE: this is pretty strict - we don't strictly need to extend the timer each time to prevent spam unlocks
//					__cancelAnyAndRebuild_unlock_timeout()
//				}
			}
			// then regardless of whether user canceled…
			fn(
				didCancel_orNil,
				validationErr_orNil,
				obtainedPasswordString
			)
		}
	}
	//
	//
	// Runtime - Imperatives - Private - Setting/changing Password
	//
	func obtainNewPasswordFromUser(isForChangePassword: Bool)
	{
		let wasFirstSetOfPasswordAtRuntime = self.hasUserEnteredValidPasswordYet == false // it's ok if we derive this here instead of in obtainNewPasswordFromUser because this fn will only be called, if setting the pw for the first time, if we have not yet accepted a valid PW yet
		self.passwordEntryDelegate.getUserToEnterNewPasswordAndType(isForChangePassword: isForChangePassword)
		{ [unowned self] (didCancel_orNil, obtainedPasswordString, userSelectedTypeOfPassword) in
			if didCancel_orNil == true {
				NotificationCenter.default.post(
					name: NotificationNames.canceledWhileEnteringNewPassword.notificationName,
					object: self
				)
				self.unguard_getNewOrExistingPassword()
				return // just silently exit after unguarding
			}
			//
			// I. Validate features of pw before trying and accepting
			if userSelectedTypeOfPassword == .PIN {
				if obtainedPasswordString!.characters.count != 6 { // this is too short. get back to them with a validation err by re-entering obtainPasswordFromUser_cb
					self.unguard_getNewOrExistingPassword()
					let err_str = "Please enter a 6-digit PIN."
					NotificationCenter.default.post(
						name: NotificationNames.erroredWhileSettingNewPassword.notificationName,
						object: self,
						userInfo: [ Notification_UserInfo_Keys.err_str.rawValue: err_str ]
					)
					return // bail
				}
				// TODO: check if all numbers
				// TODO: check that numbers are not all just one number
			} else if userSelectedTypeOfPassword == .password {
				if obtainedPasswordString!.characters.count < 6 { // this is too short. get back to them with a validation err by re-entering obtainPasswordFromUser_cb
					self.unguard_getNewOrExistingPassword()
					let err_str = "Please enter a longer password."
					NotificationCenter.default.post(
						name: NotificationNames.erroredWhileSettingNewPassword.notificationName,
						object: self,
						userInfo: [ Notification_UserInfo_Keys.err_str.rawValue: err_str ]
					)
					return // bail
				}
				// TODO: check if password content too weak?
			} else { // this is weird - code fault or cracking attempt?
				self.unguard_getNewOrExistingPassword()
				let err_str = "Unrecognized password type"
				NotificationCenter.default.post(
					name: NotificationNames.erroredWhileSettingNewPassword.notificationName,
					object: self,
					userInfo: [ Notification_UserInfo_Keys.err_str.rawValue: err_str ]
				)
				assert(false)
			}
			if isForChangePassword == true {
				if self.password == obtainedPasswordString { // they are disallowed from using change pw to enter the same pw… despite that being convenient for dev ;)
					self.unguard_getNewOrExistingPassword()
					//
					var err_str: String!
					if userSelectedTypeOfPassword == .password {
						err_str = "Please enter a fresh password."
					} else if userSelectedTypeOfPassword == .PIN {
						err_str = "Please enter a fresh PIN."
					} else {
						err_str = "Unrecognized password type"
						assert(false)
					}
					NotificationCenter.default.post(
						name: NotificationNames.erroredWhileSettingNewPassword.notificationName,
						object: self,
						userInfo: [ Notification_UserInfo_Keys.err_str.rawValue: err_str ]
					)
					return // bail
				}
			}
			//
			// II. hang onto new pw, pw type, and state(s)
			NSLog("💬  Obtained \(userSelectedTypeOfPassword) \(obtainedPasswordString!.characters.count) chars long")
			self._didObtainPassword(password: obtainedPasswordString!)
			self.passwordType = userSelectedTypeOfPassword!
			//
			// III. finally, save doc (and unlock on success) so we know a pw has been entered once before
			let err_str = self.saveToDisk()
			if err_str != nil {
				self.unguard_getNewOrExistingPassword()
				self.password = nil // they'll have to try again
				NotificationCenter.default.post(
					name: NotificationNames.erroredWhileSettingNewPassword.notificationName,
					object: self,
					userInfo: [ Notification_UserInfo_Keys.err_str.rawValue: err_str ]
				)
				return
			}
			self.unguard_getNewOrExistingPassword()
			// detecting & emiting first set or change
			if wasFirstSetOfPasswordAtRuntime == true {
				NotificationCenter.default.post(
					name: NotificationNames.setFirstPasswordDuringThisRuntime.notificationName,
					object: self
				)
			} else {
				NotificationCenter.default.post(
					name: NotificationNames.changedPassword.notificationName,
					object: self
				)
			}
			// general purpose emit
			NotificationCenter.default.post(
				name: NotificationNames.obtainedNewPassword.notificationName,
				object: self
			)
		}
	}
	//
	//
	// Imperatives - Execution deferment
	//
	var __blocksWaitingForBootToExecute: [(Void) -> Void]?
	// NOTE: onceBooted() exists because even though init()->setup() is synchronous, we need to be able to tear down and reconstruct the passwordController booted state, e.g. on user idle and delete everything
	func onceBooted(
		_ fn: @escaping ((Void) -> Void)
	)
	{
		if self.hasBooted == true {
			fn()
			return
		}
		if self.__blocksWaitingForBootToExecute == nil {
			self.__blocksWaitingForBootToExecute = []
		}
		self.__blocksWaitingForBootToExecute!.append(fn)
	}
	func _callAndFlushAllBlocksWaitingForBootToExecute()
	{
		if self.__blocksWaitingForBootToExecute == nil {
			return
		}
		let blocks = self.__blocksWaitingForBootToExecute!
		self.__blocksWaitingForBootToExecute = nil
		for (_, block) in blocks.enumerated() {
			block()
		}
	}
	//
	// Imperatives - Persistence
	func saveToDisk() -> String? // err_str?
	{
		if self.password == nil {
			let err_str = "Code fault: saveToDisk musn't be called until a password has been set"
			return err_str
		}
		let plaintextData = plaintextMessageToSaveForUnlockChallenges.data(using: .utf8)!
		let encryptedData = RNCryptor.encrypt(data: plaintextData, withPassword: self.password!)
		let encryptedData_base64String = encryptedData.base64EncodedString()
		self.messageAsEncryptedDataForUnlockChallenge_base64String = encryptedData_base64String // it's important that we hang onto this in memory so we can access it if we need to change the password later
		if self._id == nil {
			self._id = DocumentPersister.new_DocumentId()
		}
		let persistableDocument: [String: Any] =
		[
			DictKeys._id.rawValue: self._id!,
			DictKeys.passwordType.rawValue: self.passwordType.rawValue,
			DictKeys.messageAsEncryptedDataForUnlockChallenge_base64String.rawValue: self.messageAsEncryptedDataForUnlockChallenge_base64String!
		]
		let (err_str, _) = DocumentPersister.shared().Upsert(
			documentWithId: self._id!,
			inCollectionNamed: self.collectionName,
			withUpdate: persistableDocument
		)
		if err_str != nil {
			NSLog("❌  Error while persisting \(self): \(err_str!)")
		}
		//
		return err_str
	}
	
	//
	// Imperatives - Delete Everything notification registration
	func AddRegistrantForDeleteEverything(
		_ observer: DeleteEverythingRegistrant
		) -> Void
	{
		NSLog("TODO: AddRegistrantForDeleteEverything")
	}
	//
	// Delegation
	func _didObtainPassword(password: Password)
	{
		self.password = password
		self.hasUserSavedAPassword = true // we can now flip this to true
	}
}
