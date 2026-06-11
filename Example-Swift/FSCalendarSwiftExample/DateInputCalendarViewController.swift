//
//  DateInputCalendarViewController.swift
//  FSCalendarSwiftExample
//

import UIKit

class DateInputCalendarViewController: UIViewController, FSCalendarDataSource, FSCalendarDelegate, UITextFieldDelegate {

    private weak var calendar: FSCalendar!
    private weak var dateTextField: UITextField!
    private weak var statusLabel: UILabel!
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        title = "Date Input"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        title = "Date Input"
    }

    override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = UIColor.groupTableViewBackground
        self.view = view

        let height: CGFloat = UIDevice.current.model.hasPrefix("iPad") ? 450 : 300
        let top = navigationController!.navigationBar.frame.maxY

        let calendar = FSCalendar(frame: CGRect(x: 0, y: top, width: view.bounds.width, height: height))
        calendar.dataSource = self
        calendar.delegate = self
        calendar.appearance.headerDateFormat = "MMMM yyyy"
        view.addSubview(calendar)
        self.calendar = calendar

        let margin: CGFloat = 20
        let fieldY = calendar.frame.maxY + 20
        let fieldWidth = view.bounds.width - margin * 2 - 70

        let dateTextField = UITextField(frame: CGRect(x: margin, y: fieldY, width: fieldWidth, height: 44))
        dateTextField.borderStyle = .roundedRect
        dateTextField.placeholder = "yyyy-MM-dd"
        dateTextField.keyboardType = .numbersAndPunctuation
        dateTextField.autocapitalizationType = .none
        dateTextField.autocorrectionType = .no
        dateTextField.returnKeyType = .go
        dateTextField.clearButtonMode = .whileEditing
        dateTextField.delegate = self
        view.addSubview(dateTextField)
        self.dateTextField = dateTextField

        let goButton = UIButton(type: .system)
        goButton.frame = CGRect(x: dateTextField.frame.maxX + 10, y: fieldY, width: 60, height: 44)
        goButton.setTitle("Go", for: .normal)
        goButton.addTarget(self, action: #selector(loadEnteredDate), for: .touchUpInside)
        view.addSubview(goButton)

        let statusLabel = UILabel(frame: CGRect(x: margin, y: dateTextField.frame.maxY + 12, width: view.bounds.width - margin * 2, height: 40))
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = UIColor.darkGray
        statusLabel.numberOfLines = 2
        statusLabel.text = "Enter a date and tap Go to jump the calendar."
        view.addSubview(statusLabel)
        self.statusLabel = statusLabel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dateTextField.text = "1900-01-01"
        loadEnteredDate()
    }

    @objc private func loadEnteredDate() {
        let text = dateTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            statusLabel.text = "Please enter a date."
            statusLabel.textColor = .red
            return
        }

        guard let date = dateFormatter.date(from: text) else {
            statusLabel.text = "Invalid format. Use yyyy-MM-dd (e.g. 1850-06-15)."
            statusLabel.textColor = .red
            return
        }

        let minimumDate = minimumDate(for: calendar)
        let maximumDate = maximumDate(for: calendar)
        if date < minimumDate || date > maximumDate {
            statusLabel.text = "Date must be between \(dateFormatter.string(from: minimumDate)) and \(dateFormatter.string(from: maximumDate))."
            statusLabel.textColor = .red
            return
        }

        dateTextField.resignFirstResponder()
        calendar.select(date, scrollToDate: true)
        statusLabel.text = "Showing \(text)"
        statusLabel.textColor = .darkGray
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        loadEnteredDate()
        return true
    }

    func minimumDate(for calendar: FSCalendar) -> Date {
        return dateFormatter.date(from: "1800-01-01")!
    }

    func maximumDate(for calendar: FSCalendar) -> Date {
        return dateFormatter.date(from: "2025-12-31")!
    }
}
