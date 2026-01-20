// Routes.swift
// HTTP Routes for CodexBar Server
// Cross-platform: macOS and Linux

import CodexBarCore
import Foundation
import Hummingbird
import NIOCore

// MARK: - JSON Helpers

private func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted]
    let json = try encoder.encode(value)

    return Response(
        status: status,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(bytes: json))
    )
}

// MARK: - Router Builder

private struct ModelTotal: Sendable {
    let model: String
    let costUSD: Double
}

private func computeModelTotals(daily: [ProviderCostDaily]) -> [ModelTotal] {
    var totals: [String: Double] = [:]
    for entry in daily {
        for breakdown in entry.modelBreakdowns {
            totals[breakdown.modelName, default: 0] += breakdown.costUSD
        }
    }

    return totals
        .map { ModelTotal(model: $0.key, costUSD: $0.value) }
        .sorted { $0.costUSD > $1.costUSD }
}

func buildRouter(state: AppState) -> Router<BasicRequestContext> {
    let router = Router()

    // Static files
    router.get("/static/{path}") { request, context -> Response in
        let path = context.parameters.get("path") ?? ""
        guard let content = StaticFiles.get(path) else {
            return Response(status: .notFound, body: .init(byteBuffer: ByteBuffer(string: "Not found")))
        }
        let contentType = StaticFiles.contentType(for: path)
        return Response(
            status: .ok,
            headers: [.contentType: contentType],
            body: .init(byteBuffer: ByteBuffer(string: content))
        )
    }

    // Dashboard (main page)
    router.get("/") { _, _ -> Response in
        let costData = await state.getCostData()
        let html = try await DashboardPage.render(state: state, costData: costData)
        return Response(
            status: .ok,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(string: html))
        )
    }

    // Provider detail page
    router.get("/provider/{name}") { _, context -> Response in
        guard let name = context.parameters.get("name"),
              let provider = UsageProvider(rawValue: name)
        else {
            return Response(status: .notFound, body: .init(byteBuffer: ByteBuffer(string: "Provider not found")))
        }
        let html = try await ProviderPage.render(provider: provider, state: state)
        return Response(
            status: .ok,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(string: html))
        )
    }

    // API: Get all providers status
    router.get("/api/status") { _, _ -> Response in
        let latest = try await state.store.fetchLatestForAllProviders()
        let predictions = try await state.predictionEngine.predictAll(from: state.store)
        let costData = await state.getCostData()

        let statusList = latest.sorted(by: { $0.key < $1.key }).map { providerName, record in
            let prediction = predictions.first(where: { $0.provider == providerName }).map { prediction in
                APIPredictionSummary(
                    ratePerHour: prediction.ratePerHour,
                    timeToLimit: prediction.timeToLimitDescription,
                    status: prediction.status.rawValue,
                    confidence: prediction.confidence
                )
            }

            let cost = costData[providerName].map { cost in
                APICostSummary(
                    sessionTokens: cost.sessionTokens,
                    sessionCostUSD: cost.sessionCostUSD,
                    last30DaysTokens: cost.last30DaysTokens,
                    last30DaysCostUSD: cost.last30DaysCostUSD,
                    modelsUsed: cost.modelsUsed,
                    updatedAt: cost.updatedAt
                )
            }

            return APIProviderStatus(
                provider: providerName,
                timestamp: record.timestamp,
                primaryUsage: record.primaryUsedPercent,
                primaryResetAt: record.primaryResetsAt,
                secondaryUsage: record.secondaryUsedPercent,
                secondaryResetAt: record.secondaryResetsAt,
                tertiaryUsage: record.tertiaryUsedPercent,
                accountEmail: record.accountEmail,
                accountPlan: record.accountPlan,
                version: record.version,
                sourceLabel: record.sourceLabel,
                creditsRemaining: record.creditsRemaining,
                prediction: prediction,
                cost: cost
            )
        }

        return try jsonResponse(APIStatusResponse(providers: statusList))
    }

    // API: Get provider history
    router.get("/api/history/{provider}") { request, context -> Response in
        guard let name = context.parameters.get("provider"),
              let provider = UsageProvider(rawValue: name)
        else {
            return Response(status: .notFound)
        }

        let limit = request.uri.queryParameters.get("limit").flatMap(Int.init) ?? 100
        let hoursBack = request.uri.queryParameters.get("hours").flatMap(Double.init) ?? 24
        let since = Date().addingTimeInterval(-hoursBack * 3600)

        let dataPoints: [APIHistoryPoint]
        if hoursBack > 48 {
            // For long ranges, use hourly downsampled history (fast + stable payload).
            let hourly = try await state.store.fetchHourlyHistory(provider: provider, limit: 5000, since: since)
            dataPoints = hourly.map { entry in
                APIHistoryPoint(
                    timestamp: entry.timestamp,
                    primaryUsage: entry.primaryUsage,
                    primaryResetDesc: nil,
                    secondaryUsage: entry.secondaryUsage,
                    secondaryResetDesc: nil,
                    tertiaryUsage: entry.tertiaryUsage,
                    version: nil,
                    sourceLabel: nil,
                    creditsRemaining: nil
                )
            }
        } else {
            let records = try await state.store.fetchHistory(provider: provider, limit: limit, since: since)
            dataPoints = records.map { record in
                APIHistoryPoint(
                    timestamp: record.timestamp,
                    primaryUsage: record.primaryUsedPercent,
                    primaryResetDesc: record.primaryResetDesc,
                    secondaryUsage: record.secondaryUsedPercent,
                    secondaryResetDesc: record.secondaryResetDesc,
                    tertiaryUsage: record.tertiaryUsedPercent,
                    version: record.version,
                    sourceLabel: record.sourceLabel,
                    creditsRemaining: record.creditsRemaining
                )
            }
        }

        return try jsonResponse(APIHistoryResponse(provider: name, data: dataPoints))
    }

    // API: Get prediction for provider
    router.get("/api/prediction/{provider}") { request, context -> Response in
        guard let name = context.parameters.get("provider"),
              let provider = UsageProvider(rawValue: name)
        else {
            return Response(status: .notFound)
        }

        let hoursAhead = request.uri.queryParameters.get("hours").flatMap(Double.init) ?? 1.0

        guard let prediction = try await state.predictionEngine.predict(
            from: state.store,
            provider: provider,
            forHoursAhead: hoursAhead
        ) else {
            return try jsonResponse(APIErrorResponse(error: "Insufficient data for prediction"))
        }

        return try jsonResponse(
            APIPredictionResponse(
                provider: prediction.provider,
                currentUsage: prediction.currentUsage,
                predictedUsage: prediction.predictedUsage,
                calculatedAt: prediction.calculatedAt,
                predictedAt: prediction.predictedAt,
                ratePerHour: prediction.ratePerHour,
                timeToLimit: prediction.timeToLimitDescription,
                estimatedLimitDate: prediction.estimatedLimitDate,
                status: prediction.status.rawValue,
                confidence: prediction.confidence,
                dataPoints: prediction.dataPointCount
            )
        )
    }

    // API: Trigger manual fetch
    router.post("/api/fetch") { _, _ -> Response in
        await state.triggerFetch()
        return try jsonResponse(APIFetchResponse(status: "ok", message: "Fetch triggered"))
    }

    // API: Get statistics
    router.get("/api/stats/{provider}") { request, context -> Response in
        guard let name = context.parameters.get("provider"),
              let provider = UsageProvider(rawValue: name)
        else {
            return Response(status: .notFound)
        }

        let hoursBack = request.uri.queryParameters.get("hours").flatMap(Double.init) ?? 24
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-hoursBack * 3600)

        let stats = try await state.store.calculateStatistics(provider: provider, from: startDate, to: endDate)
        return try jsonResponse(
            APIStatsResponse(
                provider: stats.provider,
                periodStart: stats.periodStart,
                periodEnd: stats.periodEnd,
                recordCount: stats.recordCount,
                avgPrimaryUsage: stats.avgPrimaryUsage,
                maxPrimaryUsage: stats.maxPrimaryUsage,
                minPrimaryUsage: stats.minPrimaryUsage,
                avgSecondaryUsage: stats.avgSecondaryUsage
            )
        )
    }

    // API: Get cost data for all providers
    router.get("/api/cost") { _, _ -> Response in
        let costData = await state.getCostData()

        let costList = costData.sorted(by: { $0.key < $1.key }).map { providerName, cost in
            APICostWithProvider(
                provider: providerName,
                sessionTokens: cost.sessionTokens,
                sessionCostUSD: cost.sessionCostUSD,
                last30DaysTokens: cost.last30DaysTokens,
                last30DaysCostUSD: cost.last30DaysCostUSD,
                modelsUsed: cost.modelsUsed,
                updatedAt: cost.updatedAt
            )
        }

        return try jsonResponse(APICostResponse(costs: costList))
    }

    // API: Get cost data for specific provider
    router.get("/api/cost/{provider}") { _, context -> Response in
        guard let name = context.parameters.get("provider") else {
            return Response(status: .notFound)
        }

        guard let cost = await state.getCostData(for: name) else {
            return try jsonResponse(APIErrorResponse(error: "No cost data for provider"))
        }

        return try jsonResponse(
            APICostWithProvider(
                provider: name,
                sessionTokens: cost.sessionTokens,
                sessionCostUSD: cost.sessionCostUSD,
                last30DaysTokens: cost.last30DaysTokens,
                last30DaysCostUSD: cost.last30DaysCostUSD,
                modelsUsed: cost.modelsUsed,
                updatedAt: cost.updatedAt
            )
        )
    }

    // API: Get per-model breakdown for a provider (from latest cost snapshot)
    router.get("/api/cost/models/{provider}") { _, context -> Response in
        guard let provider = context.parameters.get("provider") else {
            return Response(status: .notFound)
        }

        guard let cost = await state.getCostData(for: provider) else {
            let json = try JSONSerialization.data(withJSONObject: ["error": "No cost data for provider"], options: .prettyPrinted)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(bytes: json))
            )
        }

        // We don't currently parse modelBreakdowns into typed structs, but the raw daily totals are
        // persisted into DB and the model list is available. For per-model filtering, expose only
        // the models list for now; the client can request full cost data if needed.
        let modelTotals = computeModelTotals(daily: cost.daily)

        let json = try JSONSerialization.data(
            withJSONObject: [
                "provider": provider,
                "models": modelTotals.map { entry in
                    [
                        "model": entry.model,
                        "costUSD": entry.costUSD,
                    ]
                },
                "updatedAt": ISO8601DateFormatter().string(from: cost.updatedAt),
            ],
            options: .prettyPrinted
        )
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // API: Get cost totals for a provider in a time range (based on stored history)
    router.get("/api/cost/range/{provider}") { request, context -> Response in
        guard let provider = context.parameters.get("provider") else {
            return Response(status: .notFound)
        }

        let hoursBack = request.uri.queryParameters.get("hours").flatMap(Int.init) ?? 24

        // Hours -> day window. (Cost data is daily-granularity.)
        let daysBack: Int = max(1, Int(ceil(Double(hoursBack) / 24.0)))

        let sinceDate = Calendar.current.date(byAdding: .day, value: -(daysBack - 1), to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let sinceDateString = formatter.string(from: sinceDate)

        let daily = try await state.store.fetchCostDaily(provider: provider, sinceDate: sinceDateString, limit: 365)

        var totalTokens = 0
        var sawTokens = false
        var totalCost = 0.0
        var sawCost = false

        for entry in daily {
            if let tokens = entry.totalTokens {
                totalTokens += tokens
                sawTokens = true
            }
            if let costValue = entry.totalCostUSD {
                totalCost += costValue
                sawCost = true
            }
        }

        let json = try JSONSerialization.data(
            withJSONObject: [
                "provider": provider,
                "hours": hoursBack,
                "days": daysBack,
                "totalTokens": (sawTokens ? totalTokens : NSNull()) as Any,
                "totalCostUSD": (sawCost ? totalCost : NSNull()) as Any,
                "recordCount": daily.count,
            ],
            options: .prettyPrinted
        )
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // API: Get cost history for a provider
    router.get("/api/cost/history/{provider}") { request, context -> Response in
        guard let name = context.parameters.get("provider") else {
            return Response(status: .notFound)
        }

        let limit = request.uri.queryParameters.get("limit").flatMap(Int.init) ?? 100
        let hoursBack = request.uri.queryParameters.get("hours").flatMap(Double.init) ?? 168 // 7 days
        let since = Date().addingTimeInterval(-hoursBack * 3600)

        let records = try await state.store.fetchCostHistory(provider: name, limit: limit, since: since)
        let dataPoints = records.map { record in
            APICostHistoryPoint(
                timestamp: record.timestamp,
                sessionTokens: record.sessionTokens,
                sessionCostUSD: record.sessionCostUSD,
                periodTokens: record.periodTokens,
                periodCostUSD: record.periodCostUSD,
                periodDays: record.periodDays,
                modelsUsed: record.models
            )
        }

        return try jsonResponse(
            APICostHistoryResponse(provider: name, data: dataPoints, recordCount: records.count)
        )
    }

    // API: Get cost history for all providers
    router.get("/api/cost/history") { request, _ -> Response in
        let limit = request.uri.queryParameters.get("limit").flatMap(Int.init) ?? 100
        let hoursBack = request.uri.queryParameters.get("hours").flatMap(Double.init) ?? 168 // 7 days
        let since = Date().addingTimeInterval(-hoursBack * 3600)

        let records = try await state.store.fetchAllCostHistory(limit: limit, since: since)
        let dataPoints = records.map { record in
            APICostHistoryPointWithProvider(
                provider: record.provider,
                timestamp: record.timestamp,
                sessionTokens: record.sessionTokens,
                sessionCostUSD: record.sessionCostUSD,
                periodTokens: record.periodTokens,
                periodCostUSD: record.periodCostUSD,
                periodDays: record.periodDays,
                modelsUsed: record.models
            )
        }

        return try jsonResponse(APICostHistoryAllResponse(data: dataPoints, recordCount: records.count))
    }

    // Health check
    router.get("/health") { _, _ -> Response in
        let usageCount = try await state.store.recordCount()
        let costCount = try await state.store.costRecordCount()

        let warnings = await state.getWarnings()
        let warningEntries = warnings.map { warning in
            APIHealthWarning(
                kind: warning.kind.rawValue,
                providers: warning.providers,
                source: warning.source,
                message: warning.message,
                lastSeenAt: warning.lastSeenAt
            )
        }

        let status = warningEntries.isEmpty ? "ok" : "warning"
        return try jsonResponse(
            APIHealthResponse(status: status, records: usageCount, costRecords: costCount, warnings: warningEntries)
        )
    }

    // API: Get recent records (across all providers)
    router.get("/api/records") { request, _ -> Response in
        let limit = request.uri.queryParameters.get("limit").flatMap(Int.init) ?? 200
        let providerName = request.uri.queryParameters.get("provider")

        let records: [UsageHistoryRecord]
        if let providerName, let provider = UsageProvider(rawValue: providerName) {
            records = try await state.store.fetchHistory(provider: provider, limit: limit)
        } else {
            records = try await state.store.fetchAllHistory(limit: limit)
        }

        return try jsonResponse(APIRecordsResponse(records: records))
    }

    // API: Get list of active providers (providers with data)
    router.get("/api/providers") { _, _ -> Response in
        let providers = try await state.store.fetchActiveProviders()
        return try jsonResponse(APIProvidersResponse(providers: providers))
    }

    return router
}

// MARK: - API Models

private struct APIErrorResponse: Codable, Sendable {
    let error: String
}

private struct APIStatusResponse: Codable, Sendable {
    let providers: [APIProviderStatus]
}

private struct APIProviderStatus: Codable, Sendable {
    let provider: String
    let timestamp: Date
    let primaryUsage: Double?
    let primaryResetAt: Date?
    let secondaryUsage: Double?
    let secondaryResetAt: Date?
    let tertiaryUsage: Double?
    let accountEmail: String?
    let accountPlan: String?
    let version: String?
    let sourceLabel: String?
    let creditsRemaining: Double?
    let prediction: APIPredictionSummary?
    let cost: APICostSummary?
}

private struct APIPredictionSummary: Codable, Sendable {
    let ratePerHour: Double
    let timeToLimit: String?
    let status: String
    let confidence: Double
}

private struct APICostSummary: Codable, Sendable {
    let sessionTokens: Int?
    let sessionCostUSD: Double?
    let last30DaysTokens: Int?
    let last30DaysCostUSD: Double?
    let modelsUsed: [String]
    let updatedAt: Date
}

private struct APIHistoryResponse: Codable, Sendable {
    let provider: String
    let data: [APIHistoryPoint]
}

private struct APIHistoryPoint: Codable, Sendable {
    let timestamp: Date
    let primaryUsage: Double?
    let primaryResetDesc: String?
    let secondaryUsage: Double?
    let secondaryResetDesc: String?
    let tertiaryUsage: Double?
    let version: String?
    let sourceLabel: String?
    let creditsRemaining: Double?
}

private struct APIPredictionResponse: Codable, Sendable {
    let provider: String
    let currentUsage: Double
    let predictedUsage: Double
    let calculatedAt: Date
    let predictedAt: Date
    let ratePerHour: Double
    let timeToLimit: String?
    let estimatedLimitDate: Date?
    let status: String
    let confidence: Double
    let dataPoints: Int
}

private struct APIFetchResponse: Codable, Sendable {
    let status: String
    let message: String
}

private struct APIStatsResponse: Codable, Sendable {
    let provider: String
    let periodStart: Date
    let periodEnd: Date
    let recordCount: Int
    let avgPrimaryUsage: Double?
    let maxPrimaryUsage: Double?
    let minPrimaryUsage: Double?
    let avgSecondaryUsage: Double?
}

private struct APICostResponse: Codable, Sendable {
    let costs: [APICostWithProvider]
}

private struct APICostWithProvider: Codable, Sendable {
    let provider: String
    let sessionTokens: Int?
    let sessionCostUSD: Double?
    let last30DaysTokens: Int?
    let last30DaysCostUSD: Double?
    let modelsUsed: [String]
    let updatedAt: Date
}

private struct APICostHistoryResponse: Codable, Sendable {
    let provider: String
    let data: [APICostHistoryPoint]
    let recordCount: Int
}

private struct APICostHistoryAllResponse: Codable, Sendable {
    let data: [APICostHistoryPointWithProvider]
    let recordCount: Int
}

private struct APICostHistoryPoint: Codable, Sendable {
    let timestamp: Date
    let sessionTokens: Int?
    let sessionCostUSD: Double?
    let periodTokens: Int?
    let periodCostUSD: Double?
    let periodDays: Int?
    let modelsUsed: [String]
}

private struct APICostHistoryPointWithProvider: Codable, Sendable {
    let provider: String
    let timestamp: Date
    let sessionTokens: Int?
    let sessionCostUSD: Double?
    let periodTokens: Int?
    let periodCostUSD: Double?
    let periodDays: Int?
    let modelsUsed: [String]
}

private struct APIHealthResponse: Codable, Sendable {
    let status: String
    let records: Int
    let costRecords: Int
    let warnings: [APIHealthWarning]
}

private struct APIHealthWarning: Codable, Sendable {
    let kind: String
    let providers: String
    let source: String
    let message: String
    let lastSeenAt: Date
}

private struct APIProvidersResponse: Codable, Sendable {
    let providers: [String]
}

private struct APIRecordsResponse: Codable, Sendable {
    let records: [UsageHistoryRecord]
}
