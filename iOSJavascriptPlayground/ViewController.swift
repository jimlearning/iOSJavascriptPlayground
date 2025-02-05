//
//  ViewController.swift
//  iOSJavascriptPlayground
//
//  Created by Jim Learning on 2025/2/5.
//

import UIKit

struct WebPage {
    let title: String
    let url: URL
}

class ViewController: UITableViewController {
    
    let pages = [
        WebPage(title: "2025年，哪16个赛道最具赚钱效应？", url: URL(string: "https://m.huxiu.com/article/3978879.html")!),
        WebPage(title: "2025年，第一家破产的造车公司出现", url: URL(string: "https://m.huxiu.com/article/3978279.html")!),
        WebPage(title: "10%关税落地，扒一扒特朗普未来的潜在大招", url: URL(string: "https://m.huxiu.com/article/3979366.html")!),
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return pages.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = pages[indexPath.row].title
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let detailVC = WebViewController(url: pages[indexPath.row].url)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

