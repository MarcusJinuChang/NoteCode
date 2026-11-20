//
//  TapTarget.swift
//  NoteCode
//
//  The smallest a control is made to answer a finger.
//

import CoreGraphics

enum TapTarget {
    /// Apple's minimum comfortable touch target. A control drawn smaller (a
    /// chevron, a colour swatch, a capsule button) is framed out to this. The
    /// hotbar's buttons are the same size but are `Hotbar.buttonSide`, which
    /// is the bar's own measurement and could change without this.
    static let minimum: CGFloat = 44
}
