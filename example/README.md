# G-code Viewer Example

A simple example application demonstrating how to use the `gcode_view` package.

## Running the example

Ensure you have Flutter installed, then:

```
cd example
flutter pub get
flutter run
```

This example demonstrates:
- Basic integration of the GcodeViewer widget
- Using a controller to reset the view
- Loading G-code files from the device
- Customizing colors and appearance
- Displaying moves
- Switching between move and rotate modes
- Configuring performance settings

## Features Demonstrated

### Basic Viewer
- Display G-code paths with different colors for cutting and travel moves
- Show/hide grid
- Pan and zoom functionality
- Reset view to initial position

### Interaction Modes
- Move Mode: Pan and zoom the view
- Rotate Mode: Rotate the view and tilt up/down

### Performance Configuration
- Level of detail rendering
- Path caching
- Maximum points to render
- Small feature preservation
- Zoom sensitivity
- Arc detail level

### File Loading
- Load G-code files from the device
- Display file information
- Handle loading states 