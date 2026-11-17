import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @State private var showNew = false
    @State private var showExchange = false
    @State private var presetType: TransactionType = .received

    struct DayPoint: Identifiable {
        let id = UUID()
        let day: String
        let received: Double
        let paid: Double
    }

    var chartData: [DayPoint] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return DayPoint(
                day: date.formatted(.dateTime.day().month(.twoDigits)),
                received: NSDecimalNumber(decimal: store.received(.USD, from: start, to: end)).doubleValue,
                paid: NSDecimalNumber(decimal: store.paid(.USD, from: start, to: end)).doubleValue
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    balanceCard
                    quickActions
                    chartCard
                    recentCard
                }
                .padding()
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Дашборд")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.preferences.hideAmounts.toggle()
                        store.save()
                    } label: {
                        Image(systemName: store.preferences.hideAmounts ? "eye.slash.fill" : "eye.fill")
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                NewTransactionView(initialType: presetType)
            }
            .sheet(isPresented: $showExchange) {
                ExchangeView()
            }
        }
    }

    private var balanceCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Остаток на руках", systemImage: "wallet.pass.fill")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.green)

                ForEach(Currency.allCases) { currency in
                    HStack {
                        Circle()
                            .fill(AppTheme.currencyColor(currency))
                            .frame(width: 46, height: 46)
                            .overlay(
                                Text(currency.symbol)
                                    .font(AppTheme.amountFont)
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading) {
                            Text(currency.rawValue).bold()
                            Text(currency.fullName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(store.preferences.hideAmounts ? "••••••" : store.cashBalance(currency).moneyText)
                            .font(AppTheme.amountFont)
                            .foregroundStyle(AppTheme.currencyColor(currency))
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            action("Гирифтам", "arrow.down", AppTheme.green) {
                presetType = .received
                showNew = true
            }

            action("Супоридам", "arrow.up", AppTheme.blue) {
                presetType = .paid
                showNew = true
            }

            action("Обмен", "arrow.triangle.2.circlepath", AppTheme.gold) {
                showExchange = true
            }
        }
    }

    private func action(
        _ title: String,
        _ icon: String,
        _ color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(AppTheme.amountFont)
                Text(title)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var chartCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("USD • последние 7 дней")
                    .font(.headline)

                Chart(chartData) { point in
                    LineMark(
                        x: .value("День", point.day),
                        y: .value("Гирифтам", point.received)
                    )
                    .foregroundStyle(AppTheme.green)

                    LineMark(
                        x: .value("День", point.day),
                        y: .value("Супоридам", point.paid)
                    )
                    .foregroundStyle(AppTheme.blue)
                }
                .frame(height: 170)
            }
        }
    }

    private var recentCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Последние операции")
                    .font(.headline)

                ForEach(store.transactions.prefix(4)) { tx in
                    TransactionRow(tx: tx)
                }
            }
        }
    }
}
