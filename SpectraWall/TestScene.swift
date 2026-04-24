//
//  TestScene.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/24.
//

import SpriteKit

class TestScene: SKScene {
    override func didMove(to view: SKView) {
        // 畫一個白色圓形在螢幕中間
        let circle = SKShapeNode(circleOfRadius: 80)
        circle.fillColor = .white
        circle.strokeColor = .clear
        circle.position = CGPoint(x: size.width / 2, y: size.height / 2)

        // 加一個上下跳動的動畫
        let moveUp = SKAction.moveBy(x: 0, y: 40, duration: 0.6)
        let moveDown = moveUp.reversed()
        moveUp.timingMode = .easeInEaseOut
        let bounce = SKAction.repeatForever(SKAction.sequence([moveUp, moveDown]))
        circle.run(bounce)

        addChild(circle)
    }
}
