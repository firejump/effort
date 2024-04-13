//
//  main.swift
//  mul_col
//
//  Created by Tomasz Kolinko on 24/01/2024.
//
import os
import Foundation
import Metal
import simd
print("starting up")

/*
print(NSUserName())
print(NSFullUserName())
 */

let server = HTTPServer.init(host: "localhost", port: 8080)
do {
//    try server.run()
} catch {
    print("server run failed")
}

let log = OSLog(subsystem: "com.kolinko", category: "Performance")
 
let gpu = Gpu()
print("loading")

//runConvert([.mixtral, .fp16])
//exit(0)

let stateDim = 4096
let hiddenDim = 14336
let goQ8 = false
let percentLoad = goQ8 ? 0x8 : 0xD // works decently for mixtral// from 0 to max binSize
let bSize: Int

var numLayers = 32
var numExperts = 1
var numTokens = 30

let goNoMuls = false
let goMistral = numExperts == 1
let goVerify = numLayers == 10 && ((numExperts == 2 && !goNoMuls && !goMistral) || goMistral)
let goSaveTests = false


//modelRunTests()
//exit(0)

let modelData = Model(numLayers: numLayers, numExperts: numExperts, percentLoad: percentLoad)

let t = Tokeniser(modelData)

//var tokens = [VectorFloat]()
let tokens = t.embed([1, 1602, 460])//[    1,   733, 16289, 28793,  1602,   460,   368, 28804,   733, 28748,
//                          16289, 28793])//!!!! [1, 1602, 460])//

os_signpost(.end, log: log, name: "Loading")

let headDim = 128  // Example head dimension
let numHeadsKV = 8
let numHeads = 32
let kvRepeats : Int = numHeads/numHeadsKV
let maxSeqLen = 2048
let maxTokens = maxSeqLen
let freqsCis = createFreqsCis2(headDim: headDim, maxSeqLen: maxSeqLen)

//modelProfile()

print()
gpu.eval()

var silent = true

var runControl = false
silent = true
//for _ in 0..<20 {
runNetwork(isTest: false, tokens: tokens, effort:1)
//numTokens = 150
//runNetwork(isTest: false, tokens: t.embed("<s>[INST]User's name is \(NSFullUserName()), datetime is 17:01, 11 Apr 2024 - write some neat like 'Good morning professor XXX, how are we doing this morning.'. And a nice quote for the day.[/INST]"), effort: 0.25)
//}

numTokens = 150

var storedIntegers: [Int] = []
var storedStrings: [String] = []

var effort: Double = 1.0 // 0.25

var isTest = false
var prevQuery : String? = nil
numTokens = 100
while true {
    print("Enter 'p XX' to store a number or any text to store it as a string ('q' to quit):")
    while true {
        print("> ", terminator: "")
        if let input = readLine() {
            if let number = Int(input), (0...100).contains(number) {
                effort = Double(number)/100.0
                if prevQuery != nil {
                    let tokens = t.embed("<s>[INST]\(prevQuery!)[/INST]")
                    runNetwork(isTest: isTest, tokens: tokens, effort:effort)
                }
            } else if input == "r" {
                // a nice simple test case
                let tq = "What's larger - Radom, Poland, or Sydney, Australia?"
                print("? \(tq)")
                let tokens = t.embed("<s>[INST]\(tq)[/INST]")
                runNetwork(isTest: isTest, tokens: tokens, effort:effort)
            } else if input == "t" {
                isTest = !isTest
                print("Test switched to " + (isTest ? "ON" : "OFF"))
            } else if input == "w" {
                let tokens = t.embed([    1,   733, 16289, 28793,  1602,   460,   368, 28804,   733, 28748,
                                          16289, 28793])
                runNetwork(isTest: isTest, tokens: tokens, effort:effort)
            } else {
                prevQuery = input
                let tokens = t.embed("<s>[INST]"+input+"[/INST]")
                runNetwork(isTest: isTest, tokens: tokens, effort:effort)
            }
        }
    }
}
