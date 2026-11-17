import Foundation

enum ExportService {
    static func csv(
        transactions: [MoneyTransaction],
        from: Date,
        to: Date
    ) -> URL? {
        var csv = "\u{FEFF}Номер,Дата,Имя,Тип,Сумма,Валюта,Доп. сумма,Доп. валюта,Комментарий\n"

        let rows = transactions.filter { $0.date >= from && $0.date <= to }

        for tx in rows {
            let safeName = tx.personName.replacingOccurrences(of: "\"", with: "\"\"")
            let safeComment = tx.comment.replacingOccurrences(of: "\"", with: "\"\"")

            csv += "\"\(tx.number)\","
            csv += "\"\(tx.date.formatted())\","
            csv += "\"\(safeName)\","
            csv += "\"\(tx.type.title)\","
            csv += "\"\(tx.amount)\","
            csv += "\"\(tx.currency.rawValue)\","
            csv += "\"\(tx.secondaryAmount?.description ?? "")\","
            csv += "\"\(tx.secondaryCurrency?.rawValue ?? "")\","
            csv += "\"\(safeComment)\"\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("P2P-Report.csv")

        do {
            try csv.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
