package {
    import flash.display.MovieClip;
    import flash.display.Shape;
    import flash.display.Stage;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.TouchEvent;
    import flash.events.MouseEvent;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;


    public class Controller {
        private var container:MovieClip;

        private var targetScale:Number = 1;
        private var minScale:Number = 1;
        private var maxScale:Number = 5;
        private var targetX:Number;
        private var targetY:Number;

        private var activeTouches:Object = {};
        private var lastTouchDistance:Number = -1;
        private var lastTouchCenter:Point = null;

        private var zoomCircle:Shape;
        private var stageRef:Stage;

        private var dragLayer:Sprite;
        private var draggingMouse:Boolean = false;
        private var lastMousePos:Point = null;

        private var debug:Boolean = true; // включи true для логов

        private var _fixedMouseX:Number = 0;
        private var _fixedMouseY:Number = 0;

        // Для контроля начала драггинга с порогом
        private var isMouseDown:Boolean = false;
        private var mouseDownPos:Point = null;
        private var isDraggingStarted:Boolean = false;
        private var isMouseDownOnContainer:Boolean = false;


        private const DRAG_THRESHOLD:Number = 5; // пикселей

        public function Controller(container:MovieClip, stageRef:Stage) {
            this.container = container;
            this.stageRef = stageRef;

            targetX = container ? container.x : 0;
            targetY = container ? container.y : 0;
            targetScale = 1;

            zoomCircle = new Shape();
            zoomCircle.graphics.beginFill(0xFF0000, 0);
            zoomCircle.graphics.drawCircle(0, 0, 10);
            zoomCircle.graphics.endFill();
            zoomCircle.visible = false;
            try {
                stageRef.addChild(zoomCircle);
            } catch (err:Error) {
                // ignore
            }

            stageRef.addEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin, false, 0, true);
            stageRef.addEventListener(TouchEvent.TOUCH_MOVE, onTouchMove, false, 0, true);
            stageRef.addEventListener(TouchEvent.TOUCH_END, onTouchEnd, false, 0, true);

            stageRef.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDownCapture, true, 1000, true);
            stageRef.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveFix, true, 1000, true);
            stageRef.addEventListener(MouseEvent.MOUSE_UP, onStageMouseUp, false, 0, true);
            stageRef.addEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel, true, 1000, true);

            stageRef.addEventListener(Event.ENTER_FRAME, onUpdate, false, 0, true);
        }

        public function dispose():void {
            try {
                stageRef.removeEventListener(TouchEvent.TOUCH_BEGIN, onTouchBegin);
                stageRef.removeEventListener(TouchEvent.TOUCH_MOVE, onTouchMove);
                stageRef.removeEventListener(TouchEvent.TOUCH_END, onTouchEnd);

                stageRef.removeEventListener(MouseEvent.MOUSE_DOWN, onMouseDownCapture, true);
                stageRef.removeEventListener(MouseEvent.MOUSE_MOVE, onMouseMoveFix, true);
                stageRef.removeEventListener(MouseEvent.MOUSE_UP, onStageMouseUp);
                stageRef.removeEventListener(MouseEvent.MOUSE_WHEEL, onMouseWheel);

                stageRef.removeEventListener(Event.ENTER_FRAME, onUpdate);
            } catch (e:Error) {
                // ignore
            }

            if (zoomCircle && zoomCircle.parent) {
                zoomCircle.parent.removeChild(zoomCircle);
            }
            if (dragLayer && dragLayer.parent) {
                dragLayer.parent.removeChild(dragLayer);
            }
            zoomCircle = null;
            dragLayer = null;
            container = null;
            activeTouches = null;
            lastMousePos = null;
            mouseDownPos = null;
        }

        private function onUpdate(e:Event):void {
            var ease:Number = 0.2;

            if (draggingMouse && lastMousePos != null) {
                var currentPos:Point = new Point(_fixedMouseX, _fixedMouseY);
                var dx:Number = currentPos.x - lastMousePos.x;
                var dy:Number = currentPos.y - lastMousePos.y;

                if (dx != 0 || dy != 0) {
                    targetX += dx;
                    targetY += dy;
                    lastMousePos = currentPos;
                    if (debug) trace("[Controller] dragging dx,dy", dx, dy, "targetX,targetY", targetX, targetY);
                }
            }

            if (container) {
                container.scaleX += (targetScale - container.scaleX) * ease;
                container.scaleY += (targetScale - container.scaleY) * ease;
                container.x += (targetX - container.x) * ease;
                container.y += (targetY - container.y) * ease;

                clampPosition(targetScale);
            }
        }

        private function clampPosition(scaleOverride:Number = -1):void {
            if (!container) return;

            var stageWidth:Number = stageRef.stageWidth;
            var stageHeight:Number = stageRef.stageHeight;

            var bounds:Rectangle = container.getBounds(container);

            var scaleVal:Number = (scaleOverride > 0) ? scaleOverride : container.scaleX;

            var scaledWidth:Number = bounds.width * scaleVal;
            var scaledHeight:Number = bounds.height * scaleVal;

            var minX:Number = stageWidth - (bounds.x + bounds.width) * scaleVal;
            var maxX:Number = -bounds.x * scaleVal;

            var minY:Number = stageHeight - (bounds.y + bounds.height) * scaleVal;
            var maxY:Number = -bounds.y * scaleVal;

            if (scaledWidth <= stageWidth) {
                targetX = (stageWidth - scaledWidth) / 2 - bounds.x * scaleVal;
            } else {
                targetX = Math.min(maxX, Math.max(minX, targetX));
            }

            if (scaledHeight <= stageHeight) {
                targetY = (stageHeight - scaledHeight) / 2 - bounds.y * scaleVal;
            } else {
                targetY = Math.min(maxY, Math.max(minY, targetY));
            }
        }

        // Touch handlers без изменений
        private function onTouchBegin(e:TouchEvent):void {
            activeTouches[e.touchPointID] = new Point(e.stageX, e.stageY);
        }

        private function onTouchMove(e:TouchEvent):void {
            activeTouches[e.touchPointID] = new Point(e.stageX, e.stageY);

            if (getTouchCount() == 2) {
                var ids:Array = getTouchIDs();
                var p1:Point = activeTouches[ids[0]];
                var p2:Point = activeTouches[ids[1]];

                var currentCenter:Point = Point.interpolate(p1, p2, 0.5);
                var currentDistance:Number = Point.distance(p1, p2);

                zoomCircle.visible = true;
                zoomCircle.x = currentCenter.x;
                zoomCircle.y = currentCenter.y;

                if (lastTouchDistance > 0) {
                    var scaleRatio:Number = currentDistance / lastTouchDistance;
                    var newScale:Number = targetScale * scaleRatio;
                    newScale = Math.max(minScale, Math.min(maxScale, newScale));

                    // 1. Центр между пальцами в global
                    var globalCenter:Point = currentCenter.clone();

                    // 2. Эта же точка в local контейнера ДО масштаба
                    var localBefore:Point = container.globalToLocal(globalCenter);

                    // 3. Обновляем целевой масштаб
                    targetScale = newScale;

                    // 4. Пересчитываем позицию так, чтобы globalCenter остался на месте
                    targetX = globalCenter.x - localBefore.x * targetScale;
                    targetY = globalCenter.y - localBefore.y * targetScale;

                    clampPosition(targetScale);
                }


                lastTouchDistance = currentDistance;
                lastTouchCenter = currentCenter.clone();
            }
        }

        private function onTouchEnd(e:TouchEvent):void {
            delete activeTouches[e.touchPointID];
            if (getTouchCount() < 2) {
                lastTouchDistance = -1;
                lastTouchCenter = null;
                zoomCircle.visible = false;
            }
        }

        private function getTouchCount():int {
            var count:int = 0;
            for (var id:* in activeTouches) count++;
            return count;
        }

        private function getTouchIDs():Array {
            var arr:Array = [];
            for (var id:* in activeTouches) arr.push(id);
            return arr;
        }

        // Mouse handlers с порогом и проверкой по контейнеру
        private function onMouseDownCapture(e:MouseEvent):void {
            var pt:Point = new Point(e.stageX, e.stageY);
            var objectsUnderPoint:Array = stageRef.getObjectsUnderPoint(pt);

            // Проверим каждый объект, есть ли тот, что не container и не потомок container
            for each (var obj:DisplayObject in objectsUnderPoint) {
                // Если это не контейнер и не его потомок
                if (obj != container && !isDescendantOf(obj, container)) {
                    if (debug) trace("[Controller] Click on other element, ignoring drag");
                    return; // Игнорируем drag
                }
            }

            // Если дошли сюда — значит клик именно по контейнеру или его потомкам
            isMouseDownOnContainer = true;
            isMouseDown = true;
            mouseDownPos = new Point(e.stageX, e.stageY);
            isDraggingStarted = false;

            if (debug) trace("[Controller] Mouse down on container");
        }

        private function isDescendantOf(child:DisplayObject, parent:DisplayObjectContainer):Boolean {
            var current:DisplayObject = child;
            while (current) {
                if (current == parent) return true;
                current = current.parent;
            }
            return false;
        }


        private function onMouseMoveFix(e:MouseEvent):void {
            _fixedMouseX = e.stageX;
            _fixedMouseY = e.stageY;

            if (!isMouseDown || !isMouseDownOnContainer || !mouseDownPos) return;

            if (!isDraggingStarted) {
                var dx:Number = _fixedMouseX - mouseDownPos.x;
                var dy:Number = _fixedMouseY - mouseDownPos.y;
                var dist:Number = Math.sqrt(dx * dx + dy * dy);

                if (dist > DRAG_THRESHOLD) {
                    isDraggingStarted = true;
                    draggingMouse = true;
                    lastMousePos = new Point(_fixedMouseX, _fixedMouseY);
                    createDragLayer();

                    if (debug) trace("[Controller] Drag started after threshold");
                }
            }
            // else — драг уже идет, обновление lastMousePos в onUpdate
        }

        private function createDragLayer():void {
            if (!dragLayer) {
                dragLayer = new Sprite();
                dragLayer.graphics.beginFill(0x000000, 0); // прозрачный
                dragLayer.graphics.drawRect(0, 0, stageRef.stageWidth, stageRef.stageHeight);
                dragLayer.graphics.endFill();
                dragLayer.mouseEnabled = true;
                dragLayer.mouseChildren = false;

                stageRef.addChild(dragLayer);
            }
        }

        private function onStageMouseUp(e:MouseEvent):void {
            isMouseDown = false;
            isMouseDownOnContainer = false;
            mouseDownPos = null;
            isDraggingStarted = false;

            if (dragLayer && dragLayer.parent) {
                dragLayer.parent.removeChild(dragLayer);
                dragLayer = null;
            }
            draggingMouse = false;
            lastMousePos = null;

            if (debug) trace("[Controller] Mouse up - drag ended or cancelled");
        }


        private function onMouseWheel(e:MouseEvent):void {
            var wheelDelta:int = e.delta;
            var factor:Number = (wheelDelta > 0) ? 1.1 : 1 / 1.1;

            var newScale:Number = targetScale * factor;
            newScale = Math.max(minScale, Math.min(maxScale, newScale));

            var globalMouse:Point = new Point(e.stageX, e.stageY);
            var localBefore:Point = container.globalToLocal(globalMouse);

            targetScale = newScale;

            targetX = globalMouse.x - localBefore.x * targetScale;
            targetY = globalMouse.y - localBefore.y * targetScale;

            clampPosition(targetScale);
        }
    }
}
