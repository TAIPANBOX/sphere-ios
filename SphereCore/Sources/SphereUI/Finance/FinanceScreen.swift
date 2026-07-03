import SwiftUI
import SphereCore

public struct FinanceScreen: View {
    private let store: FinanceStore
    /// Currency symbol from Settings (Phase 2 wires the real value).
    private let currency: String
    @State private var showingAddTransaction = false

    private let accent = SphereTheme.accent(for: .finance)

    public init(store: FinanceStore, currency: String = "$") {
        self.store = store
        self.currency = currency
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                if !store.overBudget().isEmpty {
                    overBudgetWarning
                }
                budgetsSection
                subscriptionsSection
                transactionsSection
            }
            .padding()
        }
        .navigationTitle("Finance")
        .toolbar {
            Button {
                showingAddTransaction = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionSheet { transaction in
                Task { try? await store.add(transaction) }
            }
        }
        .task {
            try? await store.load()
        }
    }

    private func money(_ value: Double) -> String {
        "\(currency)\(String(format: "%.0f", value))"
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryColumn("Income", value: store.totalIncome, tint: .green)
            Divider().frame(height: 40)
            summaryColumn("Spent", value: store.totalExpenses, tint: .red)
            Divider().frame(height: 40)
            summaryColumn("Balance", value: store.balance, tint: accent)
        }
        .sphereCard()
    }

    private func summaryColumn(_ title: String, value: Double, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(money(value))
                .font(.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Budgets

    private var overBudgetWarning: some View {
        Label(
            "Over budget: \(store.overBudget().map(\.category.label).joined(separator: ", "))",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Budgets").font(.title3.weight(.semibold))
            if store.budgets.isEmpty {
                Text("No budgets set.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.budgets) { budget in
                let spent = store.spentThisMonth(in: budget.category)
                let over = spent > budget.limit
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(budget.category.emoji) \(budget.category.label)")
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("\(money(spent)) / \(money(budget.limit))")
                            .font(.subheadline)
                            .foregroundStyle(over ? .red : .secondary)
                    }
                    ProgressView(value: min(spent, budget.limit), total: max(budget.limit, 1))
                        .tint(over ? .red : accent)
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Subscriptions

    private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Subscriptions").font(.title3.weight(.semibold))
                Spacer()
                Text("\(money(store.totalMonthlySubscriptions))/mo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.subscriptions) { subscription in
                HStack(spacing: 12) {
                    Text(subscription.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscription.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(subscription.isActive ? .primary : .secondary)
                        Text("bills in \(subscription.daysUntilBilling()) d")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(money(subscription.amount))
                        .font(.subheadline.weight(.semibold))
                    Toggle("", isOn: Binding(
                        get: { subscription.isActive },
                        set: { _ in Task { try? await store.toggleSubscription(id: subscription.id) } }
                    ))
                    .labelsHidden()
                }
                .sphereCard()
            }
        }
    }

    // MARK: - Transactions

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transactions").font(.title3.weight(.semibold))
            if store.transactions.isEmpty {
                Text("No transactions yet — add one or tell your agent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sphereCard()
            }
            ForEach(store.transactions.prefix(20)) { transaction in
                HStack(spacing: 12) {
                    Text(transaction.category.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.title).font(.body.weight(.medium))
                        Text(transaction.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((transaction.type == .income ? "+" : "-") + money(transaction.amount))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(transaction.type == .income ? .green : .primary)
                }
                .sphereCard()
            }
        }
    }
}

struct AddTransactionSheet: View {
    let onAdd: (SphereCore.Transaction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amountText = ""
    @State private var type = TransactionType.expense
    @State private var category = TransactionCategory.food

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Amount", text: $amountText)
                Picker("Type", selection: $type) {
                    Text("Expense").tag(TransactionType.expense)
                    Text("Income").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                Picker("Category", selection: $category) {
                    ForEach(TransactionCategory.allCases, id: \.self) { category in
                        Text("\(category.emoji) \(category.label)").tag(category)
                    }
                }
            }
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let amount {
                            onAdd(SphereCore.Transaction(
                                id: Transaction.newID(),
                                title: title.trimmingCharacters(in: .whitespaces),
                                amount: amount,
                                type: type,
                                category: category,
                                date: Date()
                            ))
                        }
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespaces).isEmpty
                            || amount.map { $0 <= 0 } ?? true
                    )
                }
            }
        }
    }
}
