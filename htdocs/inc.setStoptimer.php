
<!--
Stop Playout Timer Set Form
-->
        <!-- input-group -->          
        <?php
        /*
        * Values for pulldown form
        */
        $stoptimervals = array(2,5,10,15,20,30,45,60,120,180,240);
        /*
        * Get sleeptimer value
        */
        $stoptimer_epoch = exec("sudo atq -q s 2>/dev/null | awk 'NR==1{print \$3,\$4,\$5,\$6}' | xargs -r -I{} date -d '{}' +%s");
        if ($stoptimer_epoch != "") {
            $remainingstoptimerselect = round(($stoptimer_epoch - time()) / 60);
        }
        else {
            $remainingstoptimerselect = 0;
        }
        //$remainingstoptimerselect = 10; // debug
        ?>
        <div class="col-md-4 col-sm-6">
            <div class="row" style="margin-bottom:1em;">
              <div class="col-xs-6">
              <h4><?php print $lang['globalStopTimer']; ?></h4>
                <form name='stopplayoutafter' method='post' action='<?php print $_SERVER['PHP_SELF']; ?>'>
                  <div class="input-group my-group">
                    <select id="stopplayoutafter" name="stopplayoutafter" class="selectpicker form-control">
                        <option value='0'><?php print $lang['globalOff']; ?></option>
                    <?php
                    foreach($stoptimervals as $i) {
                        print "
                        <option value='".$i."'";
                        if($remainingstoptimerselect == $i) {
                            print " selected";
                        }
                        print ">".$i."min</option>";
                    }
                    print "\n";
                    ?>
                    </select> 
                    <span class="input-group-btn">
                        <input type='submit' class="btn btn-default" name='submit' value='<?php print $lang['globalSet']; ?>'/>
                    </span>
                  </div>
                </form>
              </div>
              
              <div class="col-xs-6">
                  <div class="orange c100 p<?php print round(min($remainingstoptimerselect, 60)*100/60); ?>">
                    <span><?php
                        if($remainingstoptimerselect == 0) {
                            print $lang['globalOff'];
                        } else {
                            print $remainingstoptimerselect."min";
                        }
                    ?></span>
                    <div class="slice">
                        <div class="bar"></div>
                        <div class="fill"></div>
                    </div>
                  </div> 
              </div>
            </div><!-- ./row -->
        </div>
        <!-- /input-group -->
