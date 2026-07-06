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
                        title: uiString("Start your Finance sphere"),
                        message: uiString("Log a transaction to see where your money is actually going."),
                        buttonLabel: uiString("Add your first transaction")
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
        .navigationTitle(Text(ui: "Finance"))
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
        .alert(Text(ui: "Add to goal"), isPresented: Binding(
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

    private func summaryColumn(_ title: LocalizedStringKey, value: Double, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(ui: title).font(.caption).foregroundStyle(.secondary)
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
            Label { Text(ui: "Safe to spend today") } icon: { Image(systemName: "wallet.pass.fill") }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(accent)
            Text(money(store.safeToSpendToday() ?? 0))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(ui: "Your remaining monthly budget, spread over the days left.")
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
            Text(ui: "This month by category").font(.headline)
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
            Text(ui: "More").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                MoreLink(uiString("Debts"), systemImage: "creditcard.fill",
                         count: store.debts.isEmpty ? nil : store.debts.count) { debtsList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("Investments"), systemImage: "chart.line.uptrend.xyaxis",
                         count: store.investments.isEmpty ? nil : store.investments.count) { investmentsList }
                Divider().padding(.leading, 38)
                MoreLink(uiString("Wishlist"), systemImage: "sparkles",
                         count: store.wishlist.isEmpty ? nil : store.wishlist.count) { wishlistList }
            }
            .sphereCard()
        }
    }

    private var debtsList: some View {
        CRUDListScreen(
            title: uiString("Debts"),
            items: store.debts,
            emptyTitle: uiString("No debts tracked"),
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
                        Text(ui: "\(money(debt.monthlyPayment))/mo").font(.caption).foregroundStyle(.secondary)
                    }
                }
            },
            onDelete: { debt in Task { try? await store.removeDebt(id: debt.id) } },
            onRestore: { debt in Task { try? await store.addDebt(debt) } }
        )
    }

    private var investmentsList: some View {
        CRUDListScreen(
            title: uiString("Investments"),
            items: store.investments,
            emptyTitle: uiString("No investments tracked"),
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
            title: uiString("Wishlist"),
            items: store.wishlist,
            emptyTitle: uiString("Nothing on the list"),
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
                    Text(ui: "Ready — buy it or let it go").font(.caption).foregroundStyle(.orange)
                } else {
                    Text(ui: "Cooling off · ripens in \(item.hoursUntilRipe())h")
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
                Text(ui: "Accounts").font(.title3.weight(.semibold))
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
                        Label { Text(ui: "Delete") } icon: { Image(systemName: "trash") }
                    }
                }
            }
        }
    }

    // MARK: - Savings goals

    private var savingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ui: "Savings Goals").font(.title3.weight(.semibold))
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
                        Label { Text(ui: "Delete") } icon: { Image(systemName: "trash") }
                    }
                }
            }
        }
    }

    // MARK: - Budgets

    private var overBudgetWarning: some View {
        Label {
            Text(ui: "Over budget: \(store.overBudget().map(\.category.label).joined(separator: ", "))")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sphereCard()
    }

    private var budgetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui: "Budgets").font(.title3.weight(.semibold))
            if store.budgets.isEmpty {
                Text(ui: "No budgets set.")
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
                Text(ui: "Subscriptions").font(.title3.weight(.semibold))
                Spacer()
                Text(ui: "\(money(store.totalMonthlySubscriptions))/mo")
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
                        Text(ui: "bills in \(subscription.daysUntilBilling()) d")
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
            Text(ui: "Transactions").font(.title3.weight(.semibold))
            if store.transactions.isEmpty {
                Text(ui: "No transactions yet — add one or tell your agent.")
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
                TextField(text: $name) { Text(ui: "Account name") }
                Picker(selection: $type) {
                    ForEach(AccountType.allCases, id: \.self) { type in
                        Text("\(type.emoji) \(type.label)").tag(type)
                    }
                } label: {
                    Text(ui: "Type")
                }
                TextField(text: $balanceText) { Text(ui: "Balance") }
            }
            .navigationTitle(Text(ui: "Add Account"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Account(
                            id: Account.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            type: type,
                            balance: balance
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
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
                TextField(text: $name) { Text(ui: "Goal name") }
                TextField(text: $emoji) { Text(ui: "Emoji") }
                TextField(text: $targetText) { Text(ui: "Target amount") }
            }
            .navigationTitle(Text(ui: "New Savings Goal"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let target, target > 0 {
                            onAdd(SavingsGoal(
                                id: SavingsGoal.newID(),
                                name: name.trimmingCharacters(in: .whitespaces),
                                emoji: emoji.isEmpty ? "🎯" : emoji,
                                target: target
                            ))
                        }
                        dismiss()
                    } label: {
                        Text(ui: "Add")
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
        TextField(text: $amountText) { Text(ui: "Amount") }
        Button {
            if let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) {
                onAdd(amount)
            }
        } label: {
            Text(ui: "Add")
        }
        Button(role: .cancel) {} label: { Text(ui: "Cancel") }
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
                TextField(text: $title) { Text(ui: "Title") }
                TextField(text: $amountText) { Text(ui: "Amount") }
                Picker(selection: $type) {
                    Text(ui: "Expense").tag(TransactionType.expense)
                    Text(ui: "Income").tag(TransactionType.income)
                } label: {
                    Text(ui: "Type")
                }
                .pickerStyle(.segmented)
                Picker(selection: $category) {
                    ForEach(TransactionCategory.allCases, id: \.self) { category in
                        Text("\(category.emoji) \(category.label)").tag(category)
                    }
                } label: {
                    Text(ui: "Category")
                }
            }
            .navigationTitle(Text(ui: "Add Transaction"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
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
                    } label: {
                        Text(ui: "Add")
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
                TextField(text: $name) { Text(ui: "Name (e.g. Car loan)") }
                TextField(text: $lender) { Text(ui: "Lender") }
                TextField(text: $totalText) { Text(ui: "Total amount") }
                TextField(text: $remainingText) { Text(ui: "Remaining") }
                TextField(text: $monthlyText) { Text(ui: "Monthly payment") }
            }
            .navigationTitle(Text(ui: "Add Debt"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Debt(
                            id: Debt.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            lender: lender.trimmingCharacters(in: .whitespaces),
                            totalAmount: total ?? 0,
                            remaining: remaining ?? total ?? 0,
                            monthlyPayment: Double(monthlyText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
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
                TextField(text: $name) { Text(ui: "Name") }
                Picker(selection: $type) {
                    ForEach(InvestmentType.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    Text(ui: "Type")
                }
                TextField(text: $valueText) { Text(ui: "Current value") }
            }
            .navigationTitle(Text(ui: "Add Investment"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(Investment(
                            id: Investment.newID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            type: type,
                            value: value ?? 0
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
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
                    TextField(text: $title) { Text(ui: "What do you want?") }
                    TextField(text: $amountText) { Text(ui: "Price") }
                } footer: {
                    Text(ui: "It waits 72 hours before becoming a buy-or-drop decision — a simple guard against impulse buys.")
                }
            }
            .navigationTitle(Text(ui: "Add to Wishlist"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(ui: "Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(WishlistItem(
                            id: WishlistItem.newID(),
                            title: title.trimmingCharacters(in: .whitespaces),
                            amount: amount ?? 0,
                            createdAt: Date()
                        ))
                        dismiss()
                    } label: {
                        Text(ui: "Add")
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || amount == nil)
                }
            }
        }
    }
}
