package {
    import flash.display.MovieClip;
    import flash.events.Event;
    import flash.utils.setTimeout;
    import flash.utils.clearTimeout;
    import EspControl;
    import LedController;

    public class ApartmentFilterPanel extends MovieClip {
        public var TglBtn_Occupied:ToggleButton;
        public var TglBtn_Reserved:ToggleButton;
        public var TglBtn_Available:ToggleButton;

        private static var savedFilterState:Object = {
            occupied: false,
            reserved: false,
            available: false
        };

        private var _dropdownFilters:Object = null;
        private var _lastAppliedFrame:int = -1;
        private var _buttonsInited:Boolean = false;
        private var _applyTimeoutId:uint = 0;
        private var _led:LedController = new LedController(new EspControl(AppConfig.getEspUrl()));
        private var _lightingAllowed:Boolean = false; // разрешать ли отправку подсветки

        public function ApartmentFilterPanel() {
            super();
            this.addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            // Отслеживаем смену кадра, чтобы повторно применить фильтр
            this.addEventListener(Event.FRAME_CONSTRUCTED, onFrameConstructed);
        }

        private function onAddedToStage(e:Event):void {
            this.removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
            this.gotoAndStop(1);
        }

        // Вызывается в 3-м кадре
        public function initButtons():void {
            TglBtn_Occupied  = this.getChildByName("TglBtn_Occupied")  as ToggleButton;
            TglBtn_Reserved  = this.getChildByName("TglBtn_Reserved")  as ToggleButton;
            TglBtn_Available = this.getChildByName("TglBtn_Available") as ToggleButton;

            if (!TglBtn_Occupied || !TglBtn_Reserved || !TglBtn_Available) {
                trace("[ApartmentFilterPanel] ? ToggleButton отсутствуют.");
                return;
            }

            // Восстановление сохранённого состояния
            TglBtn_Occupied.setState(savedFilterState.occupied);
            TglBtn_Reserved.setState(savedFilterState.reserved);
            TglBtn_Available.setState(savedFilterState.available);

            // Сбрасываем и перерегистрируем слушатели, чтобы не плодить дубли при переинициализации на новых кадрах
            TglBtn_Occupied.removeEventListener(ToggleButton.TOGGLE_CHANGED, onFilterChanged);
            TglBtn_Reserved.removeEventListener(ToggleButton.TOGGLE_CHANGED, onFilterChanged);
            TglBtn_Available.removeEventListener(ToggleButton.TOGGLE_CHANGED, onFilterChanged);

            TglBtn_Occupied.addEventListener(ToggleButton.TOGGLE_CHANGED, onFilterChanged);
            TglBtn_Reserved.addEventListener(ToggleButton.TOGGLE_CHANGED, onFilterChanged);
            TglBtn_Available.addEventListener(ToggleButton.TOGGLE_CHANGED, onFilterChanged);

            _buttonsInited = true;
            _lightingAllowed = false; // при входе в кадр подсветку не шлём до ручного изменения
            // Применяем фильтр сразу после инициализации, чтобы состояние отразилось без клика
            applyApartmentFilters();
        }

        private function onFrameConstructed(e:Event):void {
            // Один и тот же символ присутствует на нескольких кадрах.
            // Когда происходит смена кадра, повторно применяем фильтры, чтобы они не "глохли".
            if (currentFrame != _lastAppliedFrame) {
                _lastAppliedFrame = currentFrame;

                // После смены кадра кнопки могут быть пересозданы — пытаемся их заново найти
                if (!TglBtn_Occupied || !TglBtn_Reserved || !TglBtn_Available) {
                    _buttonsInited = false;
                }

                if (!_buttonsInited) {
                    initButtons();
                }

                if (_buttonsInited) {
                    _lightingAllowed = false; // смена кадра: фильтруем, но подсветку шлём только после ручного изменения
                    applyApartmentFilters();
                }
            }
        }

        private function onFilterChanged(e:Event):void {
            trace("[ApartmentFilterPanel] onFilterChanged triggered");

            // Сохраняем состояние toggle кнопок
            savedFilterState.occupied  = TglBtn_Occupied.state;
            savedFilterState.reserved  = TglBtn_Reserved.state;
            savedFilterState.available = TglBtn_Available.state;

            // Ручное изменение — разрешаем отправку подсветки
            _lightingAllowed = true;
            applyApartmentFilters();
        }

        public function getFilterState():Object {
            return {
                occupied:  TglBtn_Occupied ? TglBtn_Occupied.state : false,
                reserved:  TglBtn_Reserved ? TglBtn_Reserved.state : false,
                available: TglBtn_Available ? TglBtn_Available.state : false
            };
        }

        // Вызывается снаружи (например, при смене кадра), чтобы не слать подсветку до ручного изменения
        public function suppressLightingUntilUserChange():void {
            _lightingAllowed = false;
        }

        // Вызывается FiltersBar при изменении любого ToggleButton в DropDown
        public function applyDropdownFilters(filters:Object, userInitiated:Boolean = false):void {
            _dropdownFilters = filters;
            // Ручное изменение - разрешаем отправку подсветки
            if (userInitiated) {
                _lightingAllowed = true;
            }
            applyApartmentFilters();
        }

        public function applyApartmentFilters():void {
            if (_applyTimeoutId != 0) {
                clearTimeout(_applyTimeoutId);
                _applyTimeoutId = 0;
            }
            _applyTimeoutId = setTimeout(applyApartmentFiltersInternal, 30);
        }

        private function applyApartmentFiltersInternal():void {
            _applyTimeoutId = 0;
            if (!stage) {
                trace("[ApartmentFilterPanel] applyApartmentFilters: stage отсутствует, выходим");
                return;
            }

            var filters:Object = getFilterState();
            trace("[ApartmentFilterPanel] applyApartmentFilters (без слайдера площади)");
            trace("[ApartmentFilterPanel] toggle states -> occupied:" + filters.occupied +
                  " reserved:" + filters.reserved + " available:" + filters.available);

            var buttons:Array = GlobalData.apartmentButtons;

            if (!buttons) {
                trace("[ApartmentFilterPanel] Нет GlobalData.apartmentButtons для фильтрации");
                return;
            }

            // Готовим внешние фильтры с дропдаунов
            var allowedStatuses:Array = null;
            var allowedTypes:Array = null;
            var squareRanges:Array = null;

            if (_dropdownFilters) {
                if (_dropdownFilters.status && _dropdownFilters.status.length > 0) {
                    allowedStatuses = _dropdownFilters.status;
                }
                if (_dropdownFilters.type && _dropdownFilters.type.length > 0) {
                    allowedTypes = _dropdownFilters.type;
                }
                if (_dropdownFilters.square && _dropdownFilters.square.length > 0) {
                    squareRanges = _dropdownFilters.square;
                }
            }

            // Фолбэк на локальные кнопки, если внешних фильтров нет
            if (!allowedStatuses) {
                var blockedStatuses:Array = [];
                if (filters.occupied)  blockedStatuses.push("Occupied");
                if (filters.reserved)  blockedStatuses.push("Reserved");
                if (filters.available) blockedStatuses.push("Available");

                if (blockedStatuses.length > 0) {
                    allowedStatuses = [];
                    var knownStatuses:Array = ["Available", "Reserved", "Occupied", "Closed for sale"];
                    for each (var s:String in knownStatuses) {
                        if (blockedStatuses.indexOf(s) == -1) {
                            allowedStatuses.push(s);
                        }
                    }
                } else {
                    allowedStatuses = null; // все тумблеры выключены - не фильтруем
                }
            }

            trace("[ApartmentFilterPanel] dropdown statuses: " + (_dropdownFilters && _dropdownFilters.status ? _dropdownFilters.status : "none") +
                  " | allowedStatuses after merge: " + (allowedStatuses ? allowedStatuses : "none"));
            trace("[ApartmentFilterPanel] dropdown types: " + (_dropdownFilters && _dropdownFilters.type ? _dropdownFilters.type : "none"));
            trace("[ApartmentFilterPanel] dropdown square: " + (_dropdownFilters && _dropdownFilters.square ? _dropdownFilters.square : "none"));

            for each (var button:ApartmentButtonNew in buttons) {
                if (!button) {
                    continue;
                }
                try {
                    var aptNum:String = button.apartmentNumber;

                    var status:String = CRMData.getDataById(aptNum, "status");
                    var area:*        = CRMData.getDataById(aptNum, "square");
                    var aptType:*     = CRMData.getDataById(aptNum, "type");

                    if (!status || area == null) {
                        button.visible = false;
                        trace("[ApartmentFilterPanel] Квартира " + aptNum + " скрыта - нет данных");
                        continue;
                    }

                    // Нормализация возможного варианта с кириллической буквой в "Closed"
                    var normalizedStatus:String = status;
                    if (status == "Сlosed for sale") {
                        normalizedStatus = "Closed for sale";
                    }

                    var show:Boolean = true;

                    // Фильтр по статусам (разрешенные значения, если выбраны)
                    if (allowedStatuses && allowedStatuses.indexOf(normalizedStatus) == -1) {
                        show = false;
                    }

                    // Фильтр по типам
                    if (allowedTypes && allowedTypes.indexOf(aptType) == -1) {
                        show = false;
                    }

                    var areaNum:Number = Number(area);
                    if (squareRanges && show) {
                        var inRange:Boolean = false;
                        for each (var r:Object in squareRanges) {
                            if (r && areaNum >= r.min && areaNum <= r.max) {
                                inRange = true;
                                break;
                            }
                        }
                        if (!inRange) {
                            show = false;
                        }
                    }

                    button.visible = show;

                    if (!show) {
                        button.stopPulse();
                        if (GlobalData.activeButton == button) {
                            GlobalData.activeButton = null;
                        }
                    }

                    trace("[ApartmentFilterPanel] Квартира " + aptNum +
                          " | статус: " + status +
                          " | тип: " + aptType +
                          " | площадь: " + areaNum.toFixed(2) +
                          " | visible: " + show);
                } catch (err:Error) {
                    trace("[ApartmentFilterPanel] ! Ошибка при обработке кнопки: " + err.message + "\n" + err.getStackTrace());
                }
            }

            // После применения фильтров подсвечиваем только видимые квартиры одним батчем
            if (_led && _lightingAllowed) {
                _led.lightUpFilteredVisible();
            }
        }
    }
}
