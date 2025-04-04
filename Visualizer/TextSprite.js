/*
 * Copyright (C) 2021 Sienci Labs Inc.
 *
 * This file is part of gSender.
 *
 * gSender is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, under version 3 of the License.
 *
 * gSender is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with gSender.  If not, see <https://www.gnu.org/licenses/>.
 *
 * Contact for information regarding this program and its license
 * can be sent through gSender@sienci.com or mailed to the main office
 * of Sienci Labs Inc. in Waterloo, Ontario, Canada.
 *
 */

import * as THREE from 'three';

// TextSprite
class TextSprite {
    // @param {object} options The options object
    // @param {number} [options.x] The point on the x-axis
    // @param {number} [options.y] The point on the y-axis
    // @param {number} [options.z] The point on the z-axis
    // @param {string} [options.text] The text string
    // @param {string} [options.textAlign] Sets the text alignment: left|center|right
    // @param {string} [options.textBaseline] Sets the text baseline: top|middle|bottom
    // @param {number} [options.size] The actual font size
    // @param {number|string} [options.color] The color
    // @param {number} [options.opacity] The opacity of text [0,1]
    constructor(options) {
        options = options || {};
        const { opacity = 0.6, size = 10 } = options;

        const textObject = new THREE.Object3D();
        const textHeight = 100;
        let textWidth = 0;

        const canvas = document.createElement('canvas');
        const context = canvas.getContext('2d');
        context.font = 'normal ' + textHeight + 'px Arial';

        const metrics = context.measureText(options.text);
        textWidth = metrics.width;

        canvas.width = textWidth;
        canvas.height = textHeight;

        context.font = 'normal ' + textHeight + 'px Arial';
        context.textAlign = 'center';
        context.textBaseline = 'middle';
        context.fillStyle = options.color;
        context.fillText(options.text, textWidth / 2, textHeight / 2);

        const texture = new THREE.Texture(canvas);
        texture.needsUpdate = true;
        texture.minFilter = THREE.LinearFilter;

        const material = new THREE.SpriteMaterial({
            map: texture,
            transparent: true,
            opacity: opacity,
        });

        textObject.textHeight = size;
        textObject.textWidth = (textWidth / textHeight) * textObject.textHeight;

        // Position X
        if (options.textAlign === 'left') {
            textObject.position.x = options.x + textObject.textWidth / 2;
        } else if (options.textAlign === 'right') {
            textObject.position.x = options.x - textObject.textWidth / 2;
        } else {
            textObject.position.x = options.x || 0;
        }

        // Position Y
        if (options.textBaseline === 'top') {
            textObject.position.y = options.y - textObject.textHeight / 2;
        } else if (options.textBaseline === 'bottom') {
            textObject.position.y = options.y + textObject.textHeight / 2;
        } else {
            textObject.position.y = options.y || 0;
        }

        // Position Z
        textObject.position.z = options.z || 0;

        const sprite = new THREE.Sprite(material);
        sprite.scale.set((textWidth / textHeight) * size, size, 1);

        textObject.add(sprite);

        return textObject;
    }
}

export default TextSprite;
