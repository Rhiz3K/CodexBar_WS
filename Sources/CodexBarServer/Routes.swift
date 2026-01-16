// Routes.swift
// HTTP Routes for CodexBar Server
// Cross-platform: macOS and Linux

import CodexBarCore
import Foundation
import Hummingbird
import NIOCore

// MARK: - Router Builder

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
        let html = try DashboardPage.render(state: state, costData: costData)
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
        let html = try ProviderPage.render(provider: provider, state: state)
        return Response(
            status: .ok,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(string: html))
        )
    }

    // API: Get all providers status
    router.get("/api/status") { _, _ -> Response in
        let latest = try state.store.fetchLatestForAllProviders()
        let predictions = try state.predictionEngine.predictAll(from: state.store)
        let costData = await state.getCostData()

        let isoFormatter = ISO8601DateFormatter()
        var statusList: [[String: Any]] = []
        for (providerName, record) in latest {
            var entry: [String: Any] = [
                "provider": providerName,
                "timestamp": isoFormatter.string(from: record.timestamp),
                "primaryUsage": record.primaryUsedPercent as Any,
                "primaryResetAt": record.primaryResetsAt.map { isoFormatter.string(from: $0) } as Any,
                "secondaryUsage": record.secondaryUsedPercent as Any,
                "secondaryResetAt": record.secondaryResetsAt.map { isoFormatter.string(from: $0) } as Any,
                "tertiaryUsage": record.tertiaryUsedPercent as Any,
                "accountEmail": record.accountEmail as Any,
                "accountPlan": record.accountPlan as Any,
                "version": record.version as Any,
                "sourceLabel": record.sourceLabel as Any,
                "creditsRemaining": record.creditsRemaining as Any,
            ]

            if let prediction = predictions.first(where: { $0.provider == providerName }) {
                entry["prediction"] = [
                    "ratePerHour": prediction.ratePerHour,
                    "timeToLimit": prediction.timeToLimitDescription as Any,
                    "status": prediction.status.rawValue,
                    "confidence": prediction.confidence,
                ]
            }

            // Add cost data if available
            if let cost = costData[providerName] {
                entry["cost"] = [
                    "sessionTokens": cost.sessionTokens as Any,
                    "sessionCostUSD": cost.sessionCostUSD as Any,
                    "last30DaysTokens": cost.last30DaysTokens as Any,
                    "last30DaysCostUSD": cost.last30DaysCostUSD as Any,
                    "modelsUsed": cost.modelsUsed,
                    "updatedAt": isoFormatter.string(from: cost.updatedAt),
                ]
            }
            statusList.append(entry)
        }

        let json = try JSONSerialization.data(withJSONObject: ["providers": statusList], options: .prettyPrinted)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
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

        let records = try state.store.fetchHistory(provider: provider, limit: limit, since: since)

        let formatter = ISO8601DateFormatter()
        let dataPoints: [[String: Any]] = records.map { record in
            [
                "timestamp": formatter.string(from: record.timestamp),
                "primaryUsage": record.primaryUsedPercent as Any,
                "primaryResetDesc": record.primaryResetDesc as Any,
                "secondaryUsage": record.secondaryUsedPercent as Any,
                "secondaryResetDesc": record.secondaryResetDesc as Any,
                "tertiaryUsage": record.tertiaryUsedPercent as Any,
                "version": record.version as Any,
                "sourceLabel": record.sourceLabel as Any,
                "creditsRemaining": record.creditsRemaining as Any,
            ]
        }

        let json = try JSONSerialization.data(
            withJSONObject: ["provider": name, "data": dataPoints],
            options: .prettyPrinted
        )
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // API: Get prediction for provider
    router.get("/api/prediction/{provider}") { request, context -> Response in
        guard let name = context.parameters.get("provider"),
              let provider = UsageProvider(rawValue: name)
        else {
            return Response(status: .notFound)
        }

        let hoursAhead = request.uri.queryParameters.get("hours").flatMap(Double.init) ?? 1.0

        guard let prediction = try state.predictionEngine.predict(
            from: state.store,
            provider: provider,
            forHoursAhead: hoursAhead
        ) else {
            let json = try JSONSerialization.data(
                withJSONObject: ["error": "Insufficient data for prediction"],
                options: .prettyPrinted
            )
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(bytes: json))
            )
        }

        let formatter = ISO8601DateFormatter()
        let result: [String: Any] = [
            "provider": prediction.provider,
            "currentUsage": prediction.currentUsage,
            "predictedUsage": prediction.predictedUsage,
            "calculatedAt": formatter.string(from: prediction.calculatedAt),
            "predictedAt": formatter.string(from: prediction.predictedAt),
            "ratePerHour": prediction.ratePerHour,
            "timeToLimit": prediction.timeToLimitDescription as Any,
            "estimatedLimitDate": prediction.estimatedLimitDate.map { formatter.string(from: $0) } as Any,
            "status": prediction.status.rawValue,
            "confidence": prediction.confidence,
            "dataPoints": prediction.dataPointCount,
        ]

        let json = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // API: Trigger manual fetch
    router.post("/api/fetch") { _, _ -> Response in
        await state.triggerFetch()
        let json = try JSONSerialization.data(
            withJSONObject: ["status": "ok", "message": "Fetch triggered"],
            options: .prettyPrinted
        )
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
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

        let stats = try state.store.calculateStatistics(provider: provider, from: startDate, to: endDate)

        let formatter = ISO8601DateFormatter()
        let result: [String: Any] = [
            "provider": stats.provider,
            "periodStart": formatter.string(from: stats.periodStart),
            "periodEnd": formatter.string(from: stats.periodEnd),
            "recordCount": stats.recordCount,
            "avgPrimaryUsage": stats.avgPrimaryUsage as Any,
            "maxPrimaryUsage": stats.maxPrimaryUsage as Any,
            "minPrimaryUsage": stats.minPrimaryUsage as Any,
            "avgSecondaryUsage": stats.avgSecondaryUsage as Any,
        ]

        let json = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // API: Get cost data for all providers
    router.get("/api/cost") { _, _ -> Response in
        let costData = await state.getCostData()
        let isoFormatter = ISO8601DateFormatter()

        var costList: [[String: Any]] = []
        for (providerName, cost) in costData.sorted(by: { $0.key < $1.key }) {
            let entry: [String: Any] = [
                "provider": providerName,
                "sessionTokens": cost.sessionTokens as Any,
                "sessionCostUSD": cost.sessionCostUSD as Any,
                "last30DaysTokens": cost.last30DaysTokens as Any,
                "last30DaysCostUSD": cost.last30DaysCostUSD as Any,
                "modelsUsed": cost.modelsUsed,
                "updatedAt": isoFormatter.string(from: cost.updatedAt),
            ]
            costList.append(entry)
        }

        let json = try JSONSerialization.data(withJSONObject: ["costs": costList], options: .prettyPrinted)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // API: Get cost data for specific provider
    router.get("/api/cost/{provider}") { _, context -> Response in
        guard let name = context.parameters.get("provider") else {
            return Response(status: .notFound)
        }

        guard let cost = await state.getCostData(for: name) else {
            let json = try JSONSerialization.data(
                withJSONObject: ["error": "No cost data for provider"],
                options: .prettyPrinted
            )
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(bytes: json))
            )
        }

        let isoFormatter = ISO8601DateFormatter()
        let result: [String: Any] = [
            "provider": name,
            "sessionTokens": cost.sessionTokens as Any,
            "sessionCostUSD": cost.sessionCostUSD as Any,
            "last30DaysTokens": cost.last30DaysTokens as Any,
            "last30DaysCostUSD": cost.last30DaysCostUSD as Any,
            "modelsUsed": cost.modelsUsed,
            "updatedAt": isoFormatter.string(from: cost.updatedAt),
        ]

        let json = try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
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

        let records = try state.store.fetchCostHistory(provider: name, limit: limit, since: since)

        let formatter = ISO8601DateFormatter()
        let dataPoints: [[String: Any]] = records.map { record in
            [
                "timestamp": formatter.string(from: record.timestamp),
                "sessionTokens": record.sessionTokens as Any,
                "sessionCostUSD": record.sessionCostUSD as Any,
                "periodTokens": record.periodTokens as Any,
                "periodCostUSD": record.periodCostUSD as Any,
                "periodDays": record.periodDays as Any,
                "modelsUsed": record.models,
            ]
        }

        let json = try JSONSerialization.data(
            withJSONObject: ["provider": name, "data": dataPoints, "recordCount": records.count],
            options: .prettyPrinted
        )
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // API: Get cost history for all providers
    router.get("/api/cost/history") { request, _ -> Response in
        let limit = request.uri.queryParameters.get("limit").flatMap(Int.init) ?? 100
        let hoursBack = request.uri.queryParameters.get("hours").flatMap(Double.init) ?? 168 // 7 days
        let since = Date().addingTimeInterval(-hoursBack * 3600)

        let records = try state.store.fetchAllCostHistory(limit: limit, since: since)

        let formatter = ISO8601DateFormatter()
        let dataPoints: [[String: Any]] = records.map { record in
            [
                "provider": record.provider,
                "timestamp": formatter.string(from: record.timestamp),
                "sessionTokens": record.sessionTokens as Any,
                "sessionCostUSD": record.sessionCostUSD as Any,
                "periodTokens": record.periodTokens as Any,
                "periodCostUSD": record.periodCostUSD as Any,
                "periodDays": record.periodDays as Any,
                "modelsUsed": record.models,
            ]
        }

        let json = try JSONSerialization.data(
            withJSONObject: ["data": dataPoints, "recordCount": records.count],
            options: .prettyPrinted
        )
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // Health check
    router.get("/health") { _, _ -> Response in
        let usageCount = try state.store.recordCount()
        let costCount = try state.store.costRecordCount()
        let json = try JSONSerialization.data(
            withJSONObject: [
                "status": "ok",
                "records": usageCount,
                "costRecords": costCount,
            ],
            options: .prettyPrinted
        )
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    // API: Get list of active providers (providers with data)
    router.get("/api/providers") { _, _ -> Response in
        let providers = try state.store.fetchActiveProviders()
        let json = try JSONSerialization.data(
            withJSONObject: ["providers": providers],
            options: .prettyPrinted
        )
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: json))
        )
    }

    return router
}
