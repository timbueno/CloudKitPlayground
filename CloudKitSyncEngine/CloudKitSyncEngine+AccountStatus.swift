import Foundation
import CloudKit
import os.log

public enum CheckedAccountStatus: Equatable {
   case notChecked
   case checked(CKAccountStatus)
}

extension CloudKitSyncEngine {

   // MARK: - Internal

   func observeAccountStatus() {
     NotificationCenter.default.publisher(for: .CKAccountChanged, object: nil).sink { [weak self] _ in
       self?.updateAccountStatus()
     }
     .store(in: &cancellables)

     updateAccountStatus()
   }

  // MARK: - Private

  private func updateAccountStatus() {
    os_log("%{public}@", log: log, type: .debug, #function)
    container.accountStatus { [weak self] status, error in
      if let error = error {
        os_log("Error retriving iCloud account status: %{PUBLIC}@", type: .error, error.localizedDescription)
      }

      DispatchQueue.main.async {
        self?.accountStatus = .checked(status)
      }
    }
  }
}
