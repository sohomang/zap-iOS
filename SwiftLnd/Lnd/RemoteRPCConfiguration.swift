//
//  ZapShared
//
//  Created by Otto Suess on 26.06.18.
//  Copyright © 2018 Zap. All rights reserved.
//

import Foundation

public protocol RemoteRPCConfigurationType {
    var rpcConfiguration: RemoteRPCConfiguration { get }
}

public struct RemoteRPCConfiguration: Codable {
    public let certificate: String?
    public let macaroon: Macaroon
    public let url: URL
    
    public init(certificate: String?, macaroon: Macaroon, url: URL) {
        self.certificate = certificate
        self.macaroon = macaroon
        self.url = url
    }
}
