//
//  Effect.swift
//  SpectraWall
//
//  Existential protocol that lets EffectsCoordinator store any visual effect
//  in one `[UUID: any Effect]` without knowing the concrete kind. Add a new
//  effect kind by writing a class that conforms (typically via BaseEffect)
//  and registering its EffectDescriptor with EffectRegistry — nothing in the
//  coordinator or renderer needs to grow per-kind branches.
//

import Foundation

protocol Effect: AnyObject {
    var id: ObjectIdentifier { get }
    var layer: LayerSettings { get }
    var isVisible: Bool { get set }
    var opacity: Float { get set }

    func stop()
}
