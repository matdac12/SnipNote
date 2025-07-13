//
//  SupabaseManager.swift
//  SnipNote
//
//  Created by Mattia Da Campo on 13/07/25.
//

import Foundation
import Supabase

class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    private init() {
        let supabaseURL = URL(string: "https://bndbnqtvicvynzkyygte.supabase.co")!
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJuZGJucXR2aWN2eW56a3l5Z3RlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI0MTgyNDUsImV4cCI6MjA2Nzk5NDI0NX0.KJR2WxJBeTY4diMjXISBsFwFiYsniX1r0xjDIF0sgY8"
        
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }
}