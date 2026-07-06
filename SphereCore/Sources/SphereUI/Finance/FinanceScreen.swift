import SwiftUI
import Charts
import SphereCore

public struct FinanceScreen: View {
    private let store: FinanceStore
    private let currency: Currency
    @State private var showingAddTransaction = false
    @State private var showingAddAccount = false
    @State private var showingAddSavings = false
    @State private var addToGoalId: String?

    private let accent = SphereTheme.accent(for: .finance)

    public init(store: FinanceStore, currency: Currency = .usd) {
        self.store = store
        self.currency = currency
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.transactions.isEmpty && store.accounts.isEmpty && store.subscriptions.isEmpty {
                    EmptyStateCard(
                        emoji: "💰",
                        accent: accent,
                        title: "Start your Finance sphere",
                        message: "Log a transaction to see where your money is actually going.",
                        buttonLabel: "Add your first transaction"
                    ) {
                        showingAddTransaction = true
                    }
                }
                if store.safeToSpendToday() != nil {
                    safeToSpendCard
                }
                summaryCard
                if !store.overBudget().isEmpty {
                    overBudgetWarning
                }
                if !store.categorySpendingThisMonth().isEmpty {
                    categoryChartCard
                }
                accountsSection
                savingsSection
                budgetsSection
                subscriptionsSection
                moreSection
                transactionsSection
            }
            .padding()
        }
        .navigationTitle("Finance")
        .sheet(isPresented: $showingAddAccount) {
            AddAccountSheet { account in
                Task { try? await store.addAccount(account) }
            }
        }
        .sheet(isPresented: $showingAddSavings) {
            AddSavingsGoalSheet { goal in
                Task { try? await store.addSavingsGoal(goal) }
            }
        }
        .alert("Add to goal", isPresented: Binding(
            get: { addToGoalId != nil },
            set: { if !$0 { addToGoalId = nil } }
        )) {
            AddToGoalAlert(currency: currency) { amount in
                if let id = addToGoalId {
                    Task { try? await store.addToSavings(id: id, amount: amount) }
                }
                addToGoalId = nil
            }
        }
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
        currency.format(value)
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

    // MARK: - Safe to spend (gem)

    private var safeToSpendCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Safe to spend today", systemImage: "wallet.pass.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accent)
            Text(money(store.safeToSpendToday() ?? 0))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Your remaining monthly budget, spread over the days left.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    // MARK: - Category chart (gem)

    private var categoryChartCard: some View {
        let data = Array(store.categorySpendingThisMonth().prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            Text("This month by category").font(.headline)
            Chart(data, id: \.0) { entry in
                BarMark(
                    x: .value("Spent", entry.1),
                    y: .value("Category", entry.0.label)
                )
                .foregroundStyle(accent.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(money(entry.1)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(data.count) * 34 + 10)
        }
        .sphereCard()
    }

    // MARK: - More (debts, investments, wishlist)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink("Debts", systemImage: "creditcard.fill",
                         count: store.debts.isEmpty ? nil : store.debts.count) { debtsList }
                Divider().padding(.leading, 38)
                MoreLink("Investments", systemImage: "chart.line.uptrend.xyaxis",
                         count: store.investments.isEmpty ? nil : store.investments.count) { investmentsList }
                Divider().padding(.leading, 38)
                MoreLink("Wishlist", systemImage: "sparkles",
                         count: store.wishlist.isEmpty ? nil : store.wishlist.count) { wishlistList }
            }
            .sphereCard()
        }
    }

    private var debtsList: some View {
        CRUDListScreen(
            title: "Debts",
            items: store.debts,
            emptyTitle: "No debts tracked",
            emptySystemImage: "creditcard",
            addSheet: { AddDebtSheet { debt in Task { try? await store.addDebt(debt) } } },
            row: { debt in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(debt.name).font(.body.weight(.medium))
                        Spacer()
                        Text(money(debt.remaining)).font(.subheadline.weight(.semibold))
                    }
                    ProgressView(value: debt.progress).tint(accent)
                    if debt.monthlyPayment > 0 {
                        Text("\(money(debt.monthlyPayment))/mo").font(.caption).foregroundStyle(.secondary)
                    }
                }
            },
            onDelete: { debt in Task { try? await store.removeDebt(id: debt.id) } },
            onRestore: { debt in Task { try? await store.addDebt(debt) } }
        )
    }

    private var investmentsList: some View {
        CRUDListScreen(
            title: "Investments",
            items: store.investments,
            emptyTitle: "No investments tracked",
            emptySystemImage: "chart.line.uptrend.xyaxis",
            addSheet: { AddInvestmentSheet { inv in Task { try? await store.addInvestment(inv) } } },
            row: { inv in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(inv.name).font(.body.weight(.medium))
                        Text(inv.type.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(money(inv.value)).font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                }
            },
            onDelete: { inv in Task { try? await store.removeInvestment(id: inv.id) } },
            onRestore: { inv in Task { try? await store.addInvestment(inv) } }
        )
    }

    private var wishlistList: some View {
        CRUDListScreen(
            title: "Wishlist",
            items: store.wishlist,
            emptyTitle: "Nothing on the list",
            emptySystemImage: "sparkles",
            addSheet: { AddWishlistSheet { item in Task { try? await store.addWishlistItem(item) } } },
            row: { item in wishlistRow(item) },
            onDelete: { item in Task { try? await store.removeWishlistItem(id: item.id) } },
            onRestore: { item in Task { try? await store.addWishlistItem(item) } }
        )
    }

    private func wishlistRow(_ item: WishlistItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.medium))
                if item.isRipe() {
                    Text("Ready — buy it or let it go").font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Cooling off · ripens in \(item.hoursUntilRipe())h")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(money(item.amount)).font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Accounts").font(.title3.weight(.semibold))
                Spacer()
                if !store.accounts.isEmpty {
                    Text(money(store.totalAccountBalance))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                }
                Button {
                    showingAddAccount = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ForEach(store.accounts) { account in
                HStack(spacing: 12) {
                    Text(account.type.emoji).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name).font(.body.weight(.medium))
                        Text(account.type.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(money(account.balance))
                        .font(.subheadline.weight(.semibold))
                }
                .sphereCard()
                .swipeActions {
                    Button(role: .destructive) {
                        Task { try? await store.removeAccount(id: account.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Savings goals

    private var savingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Savings Goals").font(.title3.weight(.semibold))
                Spacer()
                Button {
                    showingAddSavings = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ForEach(store.savingsGoals) { goal in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(goal.emoji) \(goal.name)").font(.body.weight(.medium))
                        Spacer()
                        Button {
                            addToGoalId = goal.id
                        } label: {
                            Image(systemName: "plus.circle").foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
                    ProgressView(value: goal.percent).tint(accent)
                    HStack {
                        Text("\(money(goal.saved)) / \(money(goal.target))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(goal.percent * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
                .sphereCard()
                .swipeActions {
                    Button(role: .destructive) {
                        Task { try? await store.removeSavingsGoal(id: goal.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
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

struct AddAccountSheet: View {
    let onAdd: (Account) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = AccountType.checking
    @State private var balanceText = ""

    private var balance: Double {
        Double(balanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Account name", text: $name)
                Picker("Type", selection: $type) {
                    ForEach(AccountType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                }
                TextField("Balance", text: $balanceText)
            }
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Account(
                            id: Account.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            type: type,
                            balance: balance
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddSavingsGoalSheet: View {
    let onAdd: (SavingsGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🎯"
    @State private var targetText = ""

    private var target: Double? {
        Double(targetText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal name", text: $name)
                TextField("Emoji", text: $emoji)
                TextField("Target amount", text: $targetText)
            }
            .navigationTitle("New Savings Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let target, target > 0 {
                            onAdd(SavingsGoal(
                                id: SavingsGoal.newID(),
                                name: name.trimmingCharacters(in: .whitespaces),
                                emoji: emoji.isEmpty ? "🎯" : emoji,
                                target: target
                            ))
                        }
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                            || target.map { $0 <= 0 } ?? true
                    )
                }
            }
        }
    }
}

struct AddToGoalAlert: View {
    let currency: Currency
    let onAdd: (Double) -> Void

    @State private var amountText = ""

    var body: some View {
        TextField("Amount", text: $amountText)
        Button("Add") {
            if let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) {
                onAdd(amount)
            }
        }
        Button("Cancel", role: .cancel) {}
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

struct AddDebtSheet: View {
    let onAdd: (Debt) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var lender = ""
    @State private var totalText = ""
    @State private var remainingText = ""
    @State private var monthlyText = ""

    private var total: Double? { Double(totalText.replacingOccurrences(of: ",", with: ".")) }
    private var remaining: Double? { Double(remainingText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Car loan)", text: $name)
                TextField("Lender", text: $lender)
                TextField("Total amount", text: $totalText)
                TextField("Remaining", text: $remainingText)
                TextField("Monthly payment", text: $monthlyText)
            }
            .navigationTitle("Add Debt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Debt(
                            id: Debt.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            lender: lender.trimmingCharacters(in: .whitespaces),
                            totalAmount: total ?? 0,
                            remaining: remaining ?? total ?? 0,
                            monthlyPayment: Double(monthlyText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || total == nil)
                }
            }
        }
    }
}

struct AddInvestmentSheet: View {
    let onAdd: (Investment) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = InvestmentType.other
    @State private var valueText = ""

    private var value: Double? { Double(valueText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    ForEach(InvestmentType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Current value", text: $valueText)
            }
            .navigationTitle("Add Investment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Investment(
                            id: Investment.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            type: type,
                            value: value ?? 0
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || value == nil)
                }
            }
        }
    }
}

struct AddWishlistSheet: View {
    let onAdd: (WishlistItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amountText = ""

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want?", text: $title)
                    TextField("Price", text: $amountText)
                } footer: {
                    Text("It waits 72 hours before becoming a buy-or-drop decision — "
                        + "a simple guard against impulse buys.")
                }
            }
            .navigationTitle("Add to Wishlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(WishlistItem(
                            id: WishlistItem.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            amount: amount ?? 0,
                            createdAt: Date()
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || amount == nil)
                }
            }
        }
    }
}
