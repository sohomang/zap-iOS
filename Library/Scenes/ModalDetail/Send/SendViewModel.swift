//
//  Library
//
//  Created by Otto Suess on 18.08.18.
//  Copyright © 2018 Zap. All rights reserved.
//

import Bond
import Foundation
import Lightning
import SwiftBTC
import SwiftLnd

extension InvoiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownFormat:
            return L10n.Error.wrongUriFormat
        case let .wrongNetworkError(linkNetwork, expectedNetwork):
            return L10n.Error.wrongUriNetwork(linkNetwork.localized, expectedNetwork.localized)
        case .apiError(let localizedDescription):
            return localizedDescription
        }
    }
}

final class SendViewModel: NSObject {
    enum SendMethod {
        case lightning(PaymentRequest)
        case onChain(BitcoinURI)

        var headerImage: UIImage {
            switch self {
            case .lightning:
                return Asset.iconHeaderLightning.image
            case .onChain:
                return Asset.iconHeaderOnChain.image
            }
        }

        var headline: String {
            switch self {
            case .lightning:
                return L10n.Scene.Send.Lightning.title
            case .onChain:
                return L10n.Scene.Send.OnChain.title
            }
        }
    }

    let fee = Observable<Loadable<Satoshi?>>(.loading)

    let method: SendMethod

    let subtitleText = Observable<String?>(nil)
    let isSubtitleTextWarning = Observable(false)

    var amount: Satoshi? {
        didSet {
            guard oldValue != amount else { return }
            updateFee()
            updateIsUIEnabled()
        }
    }

    var confirmationTarget: Int = 0 {
        didSet {
            updateFee()
        }
    }

    var isSending = false {
        didSet {
            updateIsUIEnabled()
        }
    }

    lazy var maxPaymentAmount: Satoshi = {
        switch method {
        case .lightning:
            return min(LndConstants.maxLightningPaymentAllowed, lightningService.channelService.maxLocalBalance)
        case .onChain:
            return lightningService.balanceService.onChainConfirmed.value
        }
    }()

    let receiver: String
    let memo: String?
    let isSendButtonEnabled = Observable(false)
    let isInputViewEnabled = Observable(true)

    private let lightningService: LightningService

    lazy var debounceFetchFee = {
        DispatchQueue.main.debounce(interval: 275, action: fetchFee)
    }()

    init(invoice: BitcoinInvoice, lightningService: LightningService) {
        self.lightningService = lightningService

        if let paymentRequest = invoice.lightningPaymentRequest {
            method = .lightning(paymentRequest)
        } else if let bitcoinURI = invoice.bitcoinURI {
            method = .onChain(bitcoinURI)
        } else {
            fatalError("Invalid Invoice")
        }

        receiver = invoice.lightningPaymentRequest?.destination ?? invoice.bitcoinURI?.address ?? "-"
        if
            let amount = invoice.lightningPaymentRequest?.amount ?? invoice.bitcoinURI?.amount,
            amount > 0 {
            self.amount = amount
        }
        memo = invoice.lightningPaymentRequest?.memo ?? invoice.bitcoinURI?.memo

        super.init()

        updateFee()
        updateIsUIEnabled()
        updateSubtitle()
    }

    private func updateSubtitle() {
        Settings.shared.primaryCurrency
            .compactMap { [method, maxPaymentAmount] in
                guard let amount = $0.format(satoshis: maxPaymentAmount) else { return nil }
                switch method {
                case .lightning:
                    return L10n.Scene.Send.Subtitle.lightningCanSendBalance(amount)
                case .onChain:
                    return L10n.Scene.Send.Subtitle.onChainBalance(amount)
                }
            }
            .observeNext { [subtitleText] in
                subtitleText.value = $0
            }
            .dispose(in: reactive.bag)
    }

    private func updateIsUIEnabled() {
        isSendButtonEnabled.value = isAmountValid && !isSending
        isInputViewEnabled.value = !isSending
        isSubtitleTextWarning.value = amount ?? 0 > maxPaymentAmount
    }

    private var isAmountValid: Bool {
        guard let amount = amount else { return false }
        return amount > 0 && amount < maxPaymentAmount
    }

    private func updateFee() {
        if isAmountValid {
            fee.value = .loading
            updateIsUIEnabled()
            debounceFetchFee()
        } else {
            fee.value = .element(nil)
        }
    }

    private func fetchFee() {
        guard let amount = amount else { return }

        let feeCompletion = { [weak self] (result: (amount: Satoshi, fee: Satoshi?)) -> Void in
            guard
                let self = self,
                result.amount == self.amount
                else { return }

            self.fee.value = .element(result.fee)
            self.updateIsUIEnabled()
        }

        switch method {
        case .lightning(let paymentRequest):
            lightningService.transactionService.lightningFees(for: paymentRequest, amount: amount, completion: feeCompletion)
        case .onChain(let bitcoinURI):
            lightningService.transactionService.onChainFees(address: bitcoinURI.bitcoinAddress, amount: amount, confirmationTarget: confirmationTarget, completion: feeCompletion)
        }
    }

    func send(completion: @escaping ApiCompletion<Success>) {
        guard let amount = amount else { return }

        isSending = true

        let internalComplection: ApiCompletion<Success> = { [weak self] in
            if case .failure = $0 {
                self?.isSending = false
            }
            completion($0)
        }

        switch method {
        case .lightning(let paymentRequest):
            lightningService.transactionService.sendPayment(paymentRequest, amount: amount, completion: internalComplection)
        case .onChain(let bitcoinURI):
            lightningService.transactionService.sendCoins(bitcoinURI: bitcoinURI, amount: amount, confirmationTarget: confirmationTarget, completion: internalComplection)
        }
    }
}
