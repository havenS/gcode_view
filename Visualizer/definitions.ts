import { CAMERA_MODES, THEMES, VISUALIZER_TYPES } from '../../constants';

// Types

export type VISUALIZER_TYPES_T =
    (typeof VISUALIZER_TYPES)[keyof typeof VISUALIZER_TYPES];
export type CAMERA_MODES_T = (typeof CAMERA_MODES)[keyof typeof CAMERA_MODES];
export type THEMES_T = (typeof THEMES)[keyof typeof THEMES];

// Interfaces

export interface Visualizer {
    minimized: boolean;
    liteMode: boolean;
    disabled: boolean;
    disabledLite: boolean;
    minimizeRenders: boolean;
    projection: string;
    cameraMode: CAMERA_MODES_T;
    theme: THEMES_T;
    SVGEnabled: boolean;
    jobEndModal: boolean;
    gcode: {
        displayName: boolean;
    };
    objects: {
        limits: {
            visible: boolean;
        };
        coordinateSystem: {
            visible: boolean;
        };
        gridLineNumbers: {
            visible: boolean;
        };
        cuttingTool: {
            visible: boolean;
            visibleLite: boolean;
        };
        cuttingToolAnimation: {
            visible: boolean;
            visibleLite: boolean;
        };
        cutPath: {
            visible: boolean;
            visibleLite: boolean;
        };
    };
    showWarning: boolean;
    showLineWarnings: boolean;
    showSoftLimitWarning: boolean;
}
