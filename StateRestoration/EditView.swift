/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The edit view for editing a particular product.
*/

import SwiftUI

struct EditView: View {
    // The data model for storing all the products.
    @EnvironmentObject var productsViewModel: ProductsModel
    
    @Environment(\.dismiss) var dismissView
    
    @ObservedObject var product: Product

    // Whether to use product or saved values.
    @SceneStorage("EditView.useSavedValues") var useSavedValues = true
    
    // Restoration values for the edit fields.
    @State var editName: String = ""
    @State var editYear: String = ""
    @State var editPrice: String = ""
    
    // Use different width and height for info view between compact and non-compact size classes.
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    var imageWidth: CGFloat {
        horizontalSizeClass == .compact ? 100 : 280
    }
    var imageHeight: CGFloat {
        horizontalSizeClass == .compact ? 80 : 260
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("")) {
                    HStack {
                        Spacer()
                        Image(product.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageWidth, height: imageHeight)
                            .clipped()
                        Spacer()
                    }
                }

                Section(header: Text("NameTitle")) {
                    TextField("AccessibilityNameField", text: $editName)
                }
                Section(header: Text("YearTitle")) {
                    TextField("AccessibilityYearField", text: $editYear)
                        .keyboardType(.numberPad)
                }
                Section(header: Text("PriceTitle")) {
                    TextField("AccessibilityPriceField", text: $editPrice)
                        .keyboardType(.decimalPad)
                }
                Section(header: Text("")) {
                    Button("Save encrypted") {
                        saveSecurely()
                    }
                }
                Section(header: Text("")) {
                    Button("Retrieve encrypted") {
                        retrieveData()
                    }
                }
            }

            .navigationBarTitle(Text("EditProductTitle"), displayMode: .inline)
            
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CancelTitle", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("DoneTitle", action: done)
                        .disabled(editName.isEmpty)
                }
            }
        }
        
        .onAppear {
            // Decide whether or not to use the scene storage for restoration.
            if useSavedValues {
                editName = product.name
                editYear = String(product.year)
                editPrice = String(product.price)
                useSavedValues = false // Until we're dismissed, use sceneStorage values
            }
        }
    }

    func cancel() {
        dismiss()
    }
    
    func done() {
        save()
        dismiss()
    }
    
    func dismiss() {
        useSavedValues = true
        self.dismissView()
    }

    // User tapped the Done button to commit the product edit.
    func save() {
        save(product)
        productsViewModel.save()
    }
    
    func save(_ product: Product) {
        product.name = editName
        product.year = Int(editYear)!
        product.price = Double(editPrice)!
        productsViewModel.save()
    }
    
    func saveSecurely() {
        do {
            let product = Product(identifier: product.id, name: product.name, imageName: product.imageName, year: product.year, price: product.price)
            save(product)
            let data = try JSONEncoder().encode(product)
            guard let dataJsonString = String(data: data, encoding: .utf8) else {
                struct InvalidData: Error {}
                throw InvalidData()
            }
            try Encryption(fileName: product.id.uuidString).save(dataJsonString)
        } catch {
            print("ERROR::", error)
        }
    }
    
    func retrieveData() {
        do {
            let stringData = try Encryption(fileName: product.id.uuidString).retrieve()
            guard let jsonData = stringData?.data(using: .utf8) else {
                struct InvalidData: Error {}
                throw InvalidData()
            }
            let product = try JSONDecoder().decode(Product.self, from: jsonData)
            editName = product.name
            editYear = String(product.year)
            editPrice = String(product.price)
        } catch {
            print("ERROR::", error)
        }
    }
}

struct EditView_Previews: PreviewProvider {
    static var previews: some View {
        let product = Product(
            identifier: UUID(uuidString: "fa542e3d-4895-44b6-942f-e112101d5160")!,
            name: "Cherries",
            imageName: "Cherries",
            year: 2015,
            price: 10.99)
        EditView(product: product)
    }
}
