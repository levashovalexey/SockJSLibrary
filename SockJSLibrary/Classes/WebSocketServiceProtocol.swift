//
//  WebSocketServiceProtocol.swift
//  SockJS
//
//  Created by Alexey Levashov on 8/20/20.
//  Copyright © 2020 Alexey Levashov. All rights reserved.
//

import Foundation

// MARK: - Errors

enum SocketAPIError: Error {
    case invalidBaseUrl(String)
    case connectionTimeout
}

protocol WebSocketServiceProtocol {
    func connect(url: URL)
    func connect(urlRequest: URLRequest)
    func disconnect()
    func sendMessage(message: String)

    var delegate: WebSocketDelegate? { get set }
}

protocol WebSocketDelegate: class {
    func didOpen(socket: WebSocketServiceProtocol)
    func didClose(socket: WebSocketServiceProtocol, code: Int, reason: String?)
    func didReceiveMessage(socket: WebSocketServiceProtocol, message: String)
    func didReceiveData(socket: WebSocketServiceProtocol, data: Data)
    func didErrorOccured(socket: WebSocketServiceProtocol, error: Error)
}


// sourcery:begin: AutoMockable
extension WebSocketServiceProtocol {}
// sourcery:end
