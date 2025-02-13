import SwiftUI

struct DatingFiltersView: View {
  @Binding var filters: DatingFilters
  @Environment(\.dismiss) private var dismiss
  @Environment(UserViewModel.self) private var userViewModel
  @State private var showError = false
  @State private var errorMessage = ""
  let onSave: () -> Void

  init(filters: Binding<DatingFilters>, onSave: @escaping () -> Void) {

    print("[DEBUG] DatingFiltersView - Initializing - Calling UserViewModel")

    self._filters = filters
    self.onSave = onSave
    print("[DEBUG] DatingFiltersView initialized with filters: \(filters.wrappedValue)")
  }

  var body: some View {
    NavigationStack {
      Form {
        genderPreferencesSection
        distanceSection
        ageRangeSection
      }
      .navigationTitle("Dating Filters")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            Task {
              do {
                print("[DEBUG] Saving filters: \(filters)")

                // Update user model with new filter values
                userViewModel.user.interestedIn = filters.interestedIn

                // Ensure we're using the actual distance value
                if let distance = filters.maxDistance {
                  print(
                    "[DEBUG] Setting maxDistance in user model to: \(distance)")
                  userViewModel.user.maxDistance = distance
                } else {
                  print("[DEBUG] No distance value to update")
                }

                userViewModel.user.ageRange = filters.ageRange

                print(
                  "[DEBUG] About to save user with maxDistance: \(userViewModel.user.maxDistance)"
                )

                // Save to Firebase
                try await userViewModel.updateUser()
                print(
                  "[DEBUG] Successfully saved user with maxDistance: \(userViewModel.user.maxDistance)"
                )

                onSave()  // Call the callback after successful save
                dismiss()
              } catch {
                errorMessage =
                  "Failed to save filters: \(error.localizedDescription)"
                showError = true
              }
            }
          }
        }
      }
      .alert("Error", isPresented: $showError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage)
      }
      .onAppear {
        print("[DEBUG] DatingFiltersView appeared with filters: \(filters)")
      }
    }
  }

  private var genderPreferencesSection: some View {
    Section("Gender Preferences") {
      ForEach(User.Gender.allCases, id: \.self) { gender in
        GenderToggleRow(gender: gender, filters: $filters)
      }
    }
  }

  private var distanceSection: some View {
    Section("Distance") {
      DistanceSlider(
        distance: Binding(
          get: {
            let value = filters.maxDistance ?? 50
            print("[DEBUG] Distance slider getter returning: \(value)")
            return value
          },
          set: { newValue in
            print("[DEBUG] Distance slider setter called with: \(newValue)")
            filters.maxDistance = newValue
            print("[DEBUG] Distance slider updated to: \(newValue)")
          }
        ))
    }
  }

  private var ageRangeSection: some View {
    Section("Age Range") {
      AgeRangeSlider(range: $filters.ageRange)
    }
  }
}

struct GenderToggleRow: View {
  let gender: User.Gender
  @Binding var filters: DatingFilters

  private var isSelected: Bool {
    filters.interestedIn.contains(gender)
  }

  var body: some View {
    Toggle(
      gender.rawValue.capitalized,
      isOn: Binding(
        get: { isSelected },
        set: { newValue in
          if newValue && !isSelected {
            filters.interestedIn.append(gender)
          } else if !newValue {
            filters.interestedIn.removeAll { $0 == gender }
          }
        }
      ))
  }
}

struct DistanceSlider: View {
  @Binding var distance: Double
  @State private var sliderValue: Double
  private let minDistance: Double = 2  // Minimum 2 miles for safety
  private let maxDistance: Double = 250
  private let noLimitThreshold: Double = 245  // When slider reaches 245, switch to 250+
  private let unlimitedValue: Double = 100000  // Value to store in database for unlimited

  init(distance: Binding<Double>) {
    self._distance = distance
    // Initialize slider value from the binding
    let initialDistance = distance.wrappedValue
    let displayValue = initialDistance >= unlimitedValue ? maxDistance : initialDistance
    self._sliderValue = State(initialValue: displayValue)
    print(
      "[DEBUG] DistanceSlider initialized with raw value: \(initialDistance), display value: \(displayValue)"
    )
  }

  var displayText: String {
    if sliderValue >= noLimitThreshold {
      return "250+ miles"
    }
    return "\(Int(sliderValue)) miles"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Maximum Distance: \(displayText)")
        .foregroundColor(.secondary)

      Slider(
        value: $sliderValue,
        in: minDistance...maxDistance,
        step: 1
      )
      .onChange(of: sliderValue) { oldValue, newValue in
        print("[DEBUG] Slider value changed from \(oldValue) to \(newValue)")
        // Update the binding with the appropriate database value
        let newDistance = newValue >= noLimitThreshold ? unlimitedValue : newValue
        print("[DEBUG] Setting distance binding to: \(newDistance)")
        distance = newDistance
      }
    }
    .onAppear {
      print(
        "[DEBUG] DistanceSlider appeared with distance: \(distance), slider value: \(sliderValue)"
      )
    }
  }
}

struct AgeRangeSlider: View {
  @Binding var range: ClosedRange<Int>
  private let minAge = 18
  private let maxAge = 65
  private let minRange = 3  // Minimum 3 years between min and max age
  @State private var minValue: Double
  @State private var maxValue: Double

  init(range: Binding<ClosedRange<Int>>) {
    self._range = range
    self._minValue = State(initialValue: Double(range.wrappedValue.lowerBound))
    // Convert internal 100 to display max of 65
    self._maxValue = State(initialValue: Double(min(65, range.wrappedValue.upperBound)))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        "Age Range: \(Int(minValue)) - \(maxValue >= Double(maxAge) ? "65+" : "\(Int(maxValue))")"
      )
      .foregroundColor(.secondary)

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          // Background track
          Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(height: 4)

          // Selected range
          Rectangle()
            .fill(Color.blue)
            .frame(
              width: (maxValue - minValue) / Double(maxAge - minAge)
                * geometry.size.width,
              height: 4
            )
            .offset(
              x: (minValue - Double(minAge)) / Double(maxAge - minAge)
                * geometry.size.width)

          // Min thumb
          Circle()
            .fill(Color.white)
            .frame(width: 24, height: 24)
            .shadow(radius: 2)
            .offset(
              x: (minValue - Double(minAge)) / Double(maxAge - minAge)
                * geometry.size.width - 12
            )
            .gesture(
              DragGesture()
                .onChanged { value in
                  let newValue =
                    Double(minAge) + Double(maxAge - minAge) * value.location.x
                    / geometry.size.width
                  let cappedValue = min(
                    max(Double(minAge), newValue), maxValue - Double(minRange))
                  minValue = cappedValue

                  // Update the range binding with internal value (100 for 65+)
                  let internalMax =
                    maxValue >= Double(maxAge) ? 100 : Int(maxValue)
                  range = Int(minValue)...internalMax
                }
            )

          // Max thumb
          Circle()
            .fill(Color.white)
            .frame(width: 24, height: 24)
            .shadow(radius: 2)
            .offset(
              x: (maxValue - Double(minAge)) / Double(maxAge - minAge)
                * geometry.size.width - 12
            )
            .gesture(
              DragGesture(minimumDistance: 1)
                .onChanged { value in
                  let newValue =
                    Double(minAge) + Double(maxAge - minAge) * value.location.x
                    / geometry.size.width

                  // If trying to move below minimum range, push the min thumb
                  if newValue < minValue + Double(minRange) {
                    let newMin = newValue - Double(minRange)
                    if newMin >= Double(minAge) {
                      minValue = newMin
                    }
                  }

                  maxValue = min(
                    max(minValue + Double(minRange), newValue), Double(maxAge))

                  // Update the range binding with internal value (100 for 65+)
                  let internalMax =
                    maxValue >= Double(maxAge) ? 100 : Int(maxValue)
                  range = Int(minValue)...internalMax
                }
            )
        }
      }
      .frame(height: 44)
      .padding(.horizontal, 12)
    }
  }
}

#Preview {
  DatingFiltersView(filters: .constant(DatingFilters()), onSave: {})
}
