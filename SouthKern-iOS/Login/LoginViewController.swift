//
//  LoginViewController.swift
//  SendBird-iOS
//
//  Created by Jed Gyeong on 10/3/18.
//  Copyright © 2018 SendBird. All rights reserved.
//

import UIKit
import SendBirdSDK
import Photos
import Firebase
import FirebaseUI

class LoginViewController: UIViewController, UITextFieldDelegate, SBDAuthenticateDelegate, NotificationDelegate, FUIAuthDelegate {

    private var keyboardShown: Bool = false
    private var logoChanged: Bool = false
    
    @IBOutlet weak var connectButton: CustomButton!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var nicknameTextField: CustomTextField!
    @IBOutlet weak var scrollViewBottom: NSLayoutConstraint!
    @IBOutlet weak var sendbirdTextLogoImageView: UIImageView!
    @IBOutlet weak var userIdLabelTop: NSLayoutConstraint!
    @IBOutlet weak var userIdTextField: CustomTextField!
    @IBOutlet weak var versionInfoLabel: UILabel!
    
    
    // MARK: Properties
    var firebaseUser: User?
    var dataReference: DatabaseReference!
    var funcReference: Functions!
    var sendbirdUser: SBDUser?
    fileprivate(set) var firebaseAuth: Auth!
    fileprivate(set) var authUIInstance: FUIAuth?
    fileprivate var dataReferenceHandle: DatabaseHandle!
    fileprivate var authStateDidChangeHandle: AuthStateDidChangeListenerHandle!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
       
        initializeFirebaseComponents()
        setAuthHandler()
        configureFirebaseAuthUI()
        
        SBDConnectionManager.setAuthenticateDelegate(self)
        
        NotificationCenter.default.addObserver(self, selector: #selector(LoginViewController.keyboardWillShow(_:)), name: UIWindow.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(LoginViewController.keyboardWillHide(_:)), name: UIWindow.keyboardWillHideNotification, object: nil)
        let contentViewTapRecognizer = UITapGestureRecognizer.init(target: self, action: #selector(LoginViewController.tapContentView))
        
        self.contentView.isUserInteractionEnabled = true
        self.contentView.addGestureRecognizer(contentViewTapRecognizer)
        
        self.connectButton.addTarget(self, action: #selector(clickConnectButton(_ :)), for: .touchUpInside)
        
        self.userIdTextField.delegate = self
        self.nicknameTextField.delegate = self
        
        if let userId = UserDefaults.standard.object(forKey: "sendbird_user_id") as? String {
            self.userIdTextField.text = userId
        }
        if let nickname = UserDefaults.standard.object(forKey: "sendbird_user_nickname") as? String {
            self.nicknameTextField.text = nickname
        }

        // Version
        let path = Bundle.main.path(forResource: "Info", ofType: "plist")
        if path != nil {
            let infoDict = NSDictionary.init(contentsOfFile: path!)
            let sampleUIVersion = infoDict!["CFBundleShortVersionString"] as! String
            let version = String(format: "Sample UI v%@ / SDK v%@", sampleUIVersion, SBDMain.getSDKVersion())
            self.versionInfoLabel.text = version
        }
        
        let authStatus = PHPhotoLibrary.authorizationStatus()
        if authStatus != PHAuthorizationStatus.authorized {
            PHPhotoLibrary.requestAuthorization { (status) in
                
            }
        }
        
        let autoLogin = UserDefaults.standard.bool(forKey: "sendbird_auto_login")
        if autoLogin {
            self.connect()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        //authUIInstance?.auth?.removeStateDidChangeListener(authStateDidChangeHandle)
        
    }
    
    func initializeFirebaseComponents(){
        print("initializeFirebaseComponents")
        if firebaseAuth == nil {
            firebaseAuth = Auth.auth()
        }
        if dataReference == nil {
            dataReference = Database.database().reference()
        }
        if funcReference == nil{
            funcReference = Functions.functions()
        }
    }
    
    func setAuthHandler() {
        print("setAuthHandler")
        // listen for changes in the authorization state
        authStateDidChangeHandle = firebaseAuth.addStateDidChangeListener { (auth: Auth, user: User?) in
            print("checkActiveUser")
            self.checkActiveUser(user: user)
       
        }
    }
    
    func authUI(_ authUI: FUIAuth, didSignInWith authDataResult: AuthDataResult?, error: Error?) {
        print("authUI")

        switch error {
        case .some(let error as NSError) where UInt(error.code) == FUIAuthErrorCode.userCancelledSignIn.rawValue:
                print("User cancelled sign-in")
        case .some(let error as NSError) where error.userInfo[NSUnderlyingErrorKey] != nil:
            print("Login error: \(error.userInfo[NSUnderlyingErrorKey]!)")
        case .some(let error):
            print("Login error: \(error.localizedDescription)")
        case .none:
            print("No Error")
            }
        if let firebaseUser = authDataResult?.user{
            print("didSignInWith")
            setAppUserInfo(firebaseUser: firebaseUser)
        }
    }
    
    func configureFirebaseAuthUI(){
        print("configureFirebaseAuthUI")
        
            print("authUIInstance is nil")
            authUIInstance = FUIAuth.defaultAuthUI()
            authUIInstance?.delegate = self
            
            let providers: [FUIAuthProvider] = [
                FUIEmailAuth(),
                FUIGoogleAuth()
            ]
            authUIInstance?.providers = providers
            
            presentAuthViewController()
    }
    
    func setAppUserInfo(firebaseUser: User){
        print("setAppUserInfo")

        let userDefault = UserDefaults.standard
        userDefault.setValue(firebaseUser.uid, forKey: "uid")
        userDefault.setValue(firebaseUser.email , forKey: "user_id")
        userDefault.setValue(firebaseUser.displayName, forKey: "user_name")
        let photoURL = firebaseUser.photoURL?.absoluteString
        userDefault.setValue(photoURL! as NSString, forKey: "user_picture")
        
        let action: AuthTokenCallback = {(token, error) in
            if let error = error {
                print("Error on Getting Auth Token: \(error.localizedDescription)")
            }
            if let authUIToken = token {
                userDefault.setValue(authUIToken, forKey: "firebaseToken")
            }
        }
            
        firebaseUser.getIDToken(completion: action)
        userDefault.synchronize()
    }
    
    // MARK: isActiveUser
    func checkActiveUser(user: User?){
        // check if there is a current user
        print("checkActiveUser")
        if let activeUser = user {
            // check if the current app user is the current FIRUser
            if self.firebaseUser != activeUser {
                self.firebaseUser = activeUser
                self.signedInStatus(isSignedIn: true)
                
            }
        } else {
            // user must sign in
            print("user must sign in")
            self.signedInStatus(isSignedIn: false)
            self.configureFirebaseAuthUI()
        }
    }
    
    // MARK: Sign In and Out
    
    func signedInStatus(isSignedIn: Bool) {
        //connectButton.isHidden = isSignedIn
        //connectButton.isHidden = !isSignedIn
        //signOutButton.isHidden = !isSignedIn
        
        if isSignedIn {
            // remove background blur (will use when showing image messages)
            //Configure Stuff
        }
    }

    func signOut() {
        print("signOut")

        do {
            try authUIInstance?.signOut()
        } catch {
            print("unable to sign out: \(error)")
        }
    }

    
    func presentAuthViewController() {
        print("presentAuthViewController")

        let authViewController = authUIInstance?.authViewController()
        present(authViewController!, animated: true, completion: nil)
    }
    
    @objc func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrameBegin = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else  { return }
        let keyboardFrameBeginRect = keyboardFrameBegin.cgRectValue
        if self.logoChanged == false && self.keyboardShown == false {
            self.view.layoutIfNeeded()
            
            self.scrollViewBottom.constant = keyboardFrameBeginRect.size.height
            
            let animator = UIViewPropertyAnimator(duration: 0.3, curve: .easeOut) {
                self.userIdLabelTop.constant = 23
                self.sendbirdTextLogoImageView.alpha = 0
                self.view.layoutIfNeeded()
            }
            animator.startAnimation()
            
            self.logoChanged = true
        }
        else if self.logoChanged == true && self.keyboardShown == false {
            self.scrollViewBottom.constant = keyboardFrameBeginRect.size.height
        }
        
        self.keyboardShown = true
    }
    
    @objc func keyboardWillHide(_ notification: Notification) {
        self.keyboardShown = false
        self.scrollViewBottom.constant = 0
    }
    
    @objc func tapContentView() {
        if self.keyboardShown == true {
            self.view.endEditing(true)
        }
    }
    
    @objc func clickConnectButton(_ sender: Any) {
        //self.connect()
        self.signOut()
    }
    
    func connect() {
        print("connect")

        self.view.endEditing(true)
        if SBDMain.getConnectState() != .open {
            let userId = self.userIdTextField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let nickname = self.nicknameTextField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            if userId?.count == 0 || nickname?.count == 0 {
                Utils.showAlertController(title: "Error", message: "User ID and Nickname are required.", viewController: self)
                
                return
            }
            
            let userDefault = UserDefaults.standard
            userDefault.setValue(userId, forKey: "sendbird_user_id")
            userDefault.setValue(nickname, forKey: "sendbird_user_nickname")
            userDefault.synchronize()
            
            self.setUIsWhileConnecting()
            
            SBDConnectionManager.setAuthenticateDelegate(self)
            SBDConnectionManager.authenticate()
        }
        else {
            SBDMain.disconnect {
                DispatchQueue.main.async {
                    self.setUIsForDefault()
                }
            }
        }
    }

    // MARK: - UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == self.userIdTextField {
            textField.resignFirstResponder()
            self.nicknameTextField.becomeFirstResponder()
        }
        else if textField == self.nicknameTextField {
            self.connect()
        }
        
        return true
    }
    
    // MARK: - SBDAuthenticateDelegate
    func shouldHandleAuthInfo(completionHandler: @escaping (String?, String?, String?, String?) -> Void) {
        let userId = UserDefaults.standard.object(forKey: "sendbird_user_id") as? String
        completionHandler(userId, nil, nil, nil)
    }
    
    func didFinishAuthentication(with user: SBDUser?, error: SBDError?) {
        if error != nil {
            DispatchQueue.main.async {
                self.setUIsForDefault()
            }
            Utils.showAlertController(error: error!, viewController: self)
            
            return
        }
        
        UserDefaults.standard.setValue(true, forKey: "sendbird_auto_login")
        UserDefaults.standard.synchronize()
        
        DispatchQueue.main.async {
            self.setUIsForDefault()
            
            let tabBarVC = MainTabBarController.init(nibName: "MainTabBarController", bundle: nil)
            self.present(tabBarVC, animated: true, completion: nil)
        }
        
        SBDMain.getDoNotDisturb { (isDoNotDisturbOn, startHour, startMin, endHour, endMin, timezone, error) in
            UserDefaults.standard.set(startHour, forKey: "sendbird_dnd_start_hour")
            UserDefaults.standard.set(startMin, forKey: "sendbird_dnd_start_min")
            UserDefaults.standard.set(endHour, forKey: "sendbird_dnd_end_hour")
            UserDefaults.standard.set(endMin, forKey: "sendbird_dnd_end_min")
            UserDefaults.standard.set(isDoNotDisturbOn, forKey: "sendbird_dnd_on")
            UserDefaults.standard.synchronize()
        }
        
        if let deviceToken = SBDMain.getPendingPushToken() {
            SBDMain.registerDevicePushToken(deviceToken, unique: true) { (status, error) in
                if error == nil {
                    if status == SBDPushTokenRegistrationStatus.pending {
                        print("Push registration is pending.")
                    }
                    else {
                        print("APNS Token is registered.")
                    }
                }
                else {
                    print("APNS registration failed with error: \(String(describing: error))")
                }
            }
        }
        
        if let nickname = UserDefaults.standard.object(forKey: "sendbird_user_nickname") as? String {
            SBDMain.updateCurrentUserInfo(withNickname: nickname, profileUrl: nil) { (error) in
                if error != nil {
                    SBDMain.disconnect(completionHandler: {
                        Utils.showAlertController(error: error!, viewController: self)
                    })
                    
                    return
                }
            }
        }
    }
    
    // MARK: NotificationDelegate
    func openChat(_ channelUrl: String) {
        self.navigationController?.popViewController(animated: false)
        let tabBarVC = MainTabBarController.init(nibName: "MainTabBarController", bundle: nil)
        self.present(tabBarVC, animated: false) {
            let vc = UIViewController.currentViewController()
            if vc is GroupChannelsViewController {
                (vc as! GroupChannelsViewController).openChat(channelUrl)
            }
        }
    }
    
    private func setUIsWhileConnecting() {
        self.userIdTextField.isEnabled = false
        self.nicknameTextField.isEnabled = false
        self.connectButton.isEnabled = false
        self.connectButton.setTitle("Connecting...", for: .normal)
    }
    
    private func setUIsForDefault() {
        self.userIdTextField.isEnabled = true
        self.nicknameTextField.isEnabled = true
        self.connectButton.isEnabled = true
        self.connectButton.setTitle("Connect", for: .normal)
    }
}
